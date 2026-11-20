import Foundation

/// Lượt tìm của danh sách từ điển gốc (`GlobalBaseDictionaryListView`, 1.3.1037) trên `BaseDictionaryIndex` dựng sẵn.
/// Thứ tự kết quả, trần `BaseDictionaryBrowser.searchLimit`, mỗi khoá một lần:
/// 1. Lớp sửa đổi Chung (theo thứ tự của nó) — khoá chứa chuỗi tìm hoặc nghĩa hiệu lực chứa (Foundation, như cũ).
/// 2. Khoá gốc **bắt đầu** bằng chuỗi tìm, rồi khoá gốc **chứa** chuỗi tìm — quét tuyến tính mảng đơn vị UTF-16 của chỉ
///    mục (không dựng chuỗi), phân biệt hoa thường như `String.contains` cũ.
/// 3. Nghĩa gốc chứa chuỗi tìm (không phân biệt hoa thường) — so trên byte (`BaseDictionaryMeaningMatcher`), quét theo
///    lượt `workers × chunkSize` mục chia cho `workers` luồng; hết lượt mới gộp theo thứ tự chỉ mục, đủ trần thì dừng.
/// Khoá gốc đã xoá (tombstone) hoặc có ở lớp sửa đổi bị bỏ (nghĩa hiệu lực đã xét ở bước 1). Mỗi bước xong (và mỗi lượt
/// quét nghĩa có thêm kết quả) gửi bản chụp qua `emit` ⇒ màn hiện kết quả dần. Bị huỷ ⇒ dừng, không gửi bản cuối.
enum BaseDictionaryIndexSearch {
    private static let chunkSize = 16_384
    /// Đối chiếu đường byte với Foundation trên chừng này nghĩa đầu mỗi lượt tìm — số lệch ghi log (kiểm trên máy).
    private static let crossCheckSampleSize = 1_000

    static func run(
        _ query: String,
        index: BaseDictionaryIndex?,
        custom: [(key: String, value: String)],
        deleted: Set<String>,
        workers: Int,
        label: String,
        emit: (BaseDictionaryBrowser.SearchResult) -> Void
    ) {
        let limit = BaseDictionaryBrowser.searchLimit
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            emit(.init(keys: [], isCapped: false, isComplete: true))
            return
        }
        let started = Date()
        var found: [String] = []
        var seen = Set<String>()
        var customKeys = Set<String>()
        for entry in custom {
            customKeys.insert(entry.key)
            guard found.count < limit,
                  entry.key.contains(needle) || entry.value.range(of: needle, options: .caseInsensitive) != nil,
                  seen.insert(entry.key).inserted else { continue }
            found.append(entry.key)
        }
        guard let index, found.count < limit else {
            emit(.init(keys: found, isCapped: found.count >= limit, isComplete: true))
            return
        }
        func accept(_ key: String) -> Bool {
            !deleted.contains(key) && !customKeys.contains(key) && seen.insert(key).inserted
        }

        // 2. Khoá.
        guard let keyHits = keyMatches(Array(needle.utf16), in: index, room: limit - found.count, accept: accept) else {
            return logCancelled(label, needle, started)
        }
        found += keyHits.prefix + keyHits.contains
        let keyMs = Date().timeIntervalSince(started) * 1000
        guard found.count < limit else {
            emit(.init(keys: Array(found.prefix(limit)), isCapped: true, isComplete: true))
            return logDone(label, needle, keyMs, keyHits, meaning: nil, found.count, capped: true)
        }
        emit(.init(keys: found, isCapped: false, isComplete: false))

        // 3. Nghĩa.
        let matcher = BaseDictionaryMeaningMatcher(needle: needle)
        let meaningStarted = Date()
        var stats = MeaningStats(workers: max(1, workers))
        stats.mismatches = crossCheck(matcher, index: index)
        var next = 0
        var capped = false
        while next < index.count, !capped {
            if Task.isCancelled { return logCancelled(label, needle, started) }
            let roundEnd = min(index.count, next + stats.workers * chunkSize)
            let (hits, slow) = scanMeanings(matcher, index: index, range: next..<roundEnd, workers: stats.workers)
            stats.slowPath += slow
            stats.scanned = roundEnd
            next = roundEnd
            let before = found.count
            for hit in hits {
                let key = index.key(at: hit)
                guard accept(key) else { continue }
                found.append(key)
                if found.count >= limit { capped = true; break }
            }
            if found.count > before, !capped, next < index.count {
                emit(.init(keys: found, isCapped: false, isComplete: false))
            }
        }
        if Task.isCancelled { return logCancelled(label, needle, started) }
        emit(.init(keys: found, isCapped: capped, isComplete: true))
        stats.ms = Date().timeIntervalSince(meaningStarted) * 1000
        logDone(label, needle, keyMs, keyHits, meaning: stats, found.count, capped: capped)
    }

    // MARK: - Khoá

    private struct KeyHits {
        var prefix: [String] = []
        var contains: [String] = []
    }

    /// Khoá bắt đầu bằng / chứa `needle` (tối đa `room` mỗi loại). Đủ `room` khoá bắt đầu bằng ⇒ dừng (phần chứa không
    /// còn chỗ). `nil` khi bị huỷ.
    private static func keyMatches(
        _ needle: [UInt16], in index: BaseDictionaryIndex, room: Int, accept: (String) -> Bool
    ) -> KeyHits? {
        var hits = KeyHits()
        let length = needle.count
        var cancelled = false
        index.keyUnits.withUnsafeBufferPointer { units in
            index.keyStart.withUnsafeBufferPointer { starts in
                needle.withUnsafeBufferPointer { pattern in
                    for entry in 0..<index.count {
                        if entry & 0xFFFF == 0, Task.isCancelled { cancelled = true; return }
                        let start = Int(starts[entry])
                        let keyLength = Int(starts[entry + 1]) - start
                        guard keyLength >= length else { continue }
                        guard let at = firstOccurrence(of: pattern, in: units, from: start, count: keyLength) else { continue }
                        if at == start {
                            guard hits.prefix.count < room else { continue }
                            let key = index.key(at: entry)
                            if accept(key) { hits.prefix.append(key) }
                            if hits.prefix.count >= room { return }
                        } else if hits.contains.count < room {
                            let key = index.key(at: entry)
                            if accept(key) { hits.contains.append(key) }
                        }
                    }
                }
            }
        }
        if cancelled { return nil }
        hits.contains = Array(hits.contains.prefix(max(0, room - hits.prefix.count)))
        return hits
    }

    private static func firstOccurrence(
        of pattern: UnsafeBufferPointer<UInt16>, in units: UnsafeBufferPointer<UInt16>, from start: Int, count: Int
    ) -> Int? {
        let last = start + count - pattern.count
        guard let first = pattern.first, last >= start else { return nil }
        var position = start
        while position <= last {
            if units[position] == first {
                var offset = 1
                while offset < pattern.count, units[position + offset] == pattern[offset] { offset += 1 }
                if offset == pattern.count { return position }
            }
            position += 1
        }
        return nil
    }

    // MARK: - Nghĩa

    private struct MeaningStats {
        let workers: Int
        var scanned = 0
        var slowPath = 0
        var mismatches = 0
        var ms: Double = 0
    }

    /// Quét nghĩa của `range` bằng `workers` luồng; trả chỉ số khớp theo thứ tự + số nghĩa phải so bằng Foundation.
    private static func scanMeanings(
        _ matcher: BaseDictionaryMeaningMatcher, index: BaseDictionaryIndex, range: Range<Int>, workers: Int
    ) -> (hits: [Int], slowPath: Int) {
        let sliceSize = (range.count + workers - 1) / workers
        var perWorker = [[Int]](repeating: [], count: workers)
        var slowPerWorker = [Int](repeating: 0, count: workers)
        index.valueData.withUnsafeBytes { raw in
            index.valueOffset.withUnsafeBufferPointer { offsets in
                perWorker.withUnsafeMutableBufferPointer { resultsBuffer in
                    slowPerWorker.withUnsafeMutableBufferPointer { slowBuffer in
                        // Bản `let` của con trỏ (tham số `inout` không được bắt trong closure chạy song song); mỗi luồng
                        // chỉ ghi ô của chính nó.
                        let results = resultsBuffer
                        let slowCounts = slowBuffer
                        DispatchQueue.concurrentPerform(iterations: workers) { worker in
                            let lower = range.lowerBound + worker * sliceSize
                            let upper = min(range.upperBound, lower + sliceSize)
                            guard lower < upper else { return }
                            var scratch: [UInt32] = []
                            scratch.reserveCapacity(128)
                            var hits: [Int] = []
                            var slow = 0
                            for entry in lower..<upper {
                                guard let valueRange = BaseDictionaryIndex.valueRange(
                                    at: Int(offsets[entry]), dataCount: raw.count, byteAt: { raw[$0] }
                                ) else { continue }
                                let bytes = UnsafeRawBufferPointer(rebasing: raw[valueRange])
                                switch matcher.match(bytes, scratch: &scratch) {
                                case .match:
                                    hits.append(entry)
                                case .noMatch:
                                    break
                                case .needsFoundation:
                                    slow += 1
                                    if let value = String(bytes: bytes, encoding: .utf8), matcher.foundationMatches(value) {
                                        hits.append(entry)
                                    }
                                }
                            }
                            results[worker] = hits
                            slowCounts[worker] = slow
                        }
                    }
                }
            }
        }
        return (perWorker.flatMap { $0 }, slowPerWorker.reduce(0, +))
    }

    /// Số nghĩa (trong `crossCheckSampleSize` mục đầu) mà đường byte và Foundation cho kết quả khác nhau.
    private static func crossCheck(_ matcher: BaseDictionaryMeaningMatcher, index: BaseDictionaryIndex) -> Int {
        var mismatches = 0
        var scratch: [UInt32] = []
        index.valueData.withUnsafeBytes { raw in
            for entry in 0..<min(index.count, crossCheckSampleSize) {
                guard let valueRange = BaseDictionaryIndex.valueRange(
                    at: Int(index.valueOffset[entry]), dataCount: raw.count, byteAt: { raw[$0] }
                ) else { continue }
                let bytes = UnsafeRawBufferPointer(rebasing: raw[valueRange])
                let fast: Bool
                switch matcher.match(bytes, scratch: &scratch) {
                case .match: fast = true
                case .noMatch: fast = false
                case .needsFoundation: continue
                }
                let reference = String(bytes: bytes, encoding: .utf8).map(matcher.foundationMatches) ?? false
                if fast != reference { mismatches += 1 }
            }
        }
        return mismatches
    }

    // MARK: - Log

    private static func logCancelled(_ label: String, _ needle: String, _ started: Date) {
        let ms = Date().timeIntervalSince(started) * 1000
        AppLogger.shared.log("🔎 [VPList] Tìm \"\(needle)\" trong \(label): huỷ sau \(String(format: "%.0f", ms)) ms (gõ tiếp)")
    }

    private static func logDone(
        _ label: String, _ needle: String, _ keyMs: Double, _ keys: KeyHits,
        meaning: MeaningStats?, _ total: Int, capped: Bool
    ) {
        var line = "🔎 [VPList] Tìm \"\(needle)\" trong \(label): khoá \(String(format: "%.0f", keyMs)) ms "
            + "(bắt đầu bằng \(keys.prefix.count), chứa \(keys.contains.count))"
        if let meaning {
            line += ", nghĩa \(String(format: "%.0f", meaning.ms)) ms (\(meaning.scanned) mục, \(meaning.workers) luồng, "
                + "so Foundation \(meaning.slowPath), đối chiếu \(crossCheckSampleSize) nghĩa lệch \(meaning.mismatches))"
        } else {
            line += ", không quét nghĩa"
        }
        line += " ⇒ \(total) kết quả\(capped ? " (đủ trần)" : "")"
        AppLogger.shared.log(line)
    }
}
