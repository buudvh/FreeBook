import Foundation

/// Bước "Đang chuẩn bị quét…" của quét tên riêng nhiều chương (1.3.602): đọc văn bản các chương đã chọn, chuẩn hoá,
/// rồi chia lượt.
///
/// Trước 1.3.602 mỗi chương một lần nhảy actor `BookBinManager` + `fileExists` + mở/seek/đọc/đóng `FileHandle`, rồi
/// chuẩn hoá (lọc rác bằng regex của người dùng + tách dòng) **tuần tự** — truyện vài nghìn chương chờ rất lâu. Nay đọc
/// theo khối `chunkSize` chương, mỗi khối **một** lần gọi actor với một `FileHandle` (không giữ actor suốt cả lần quét),
/// chuẩn hoá khối đó song song (tối đa `maxNormalizeWidth` luồng), giữ nguyên thứ tự chương. Chuẩn hoá vẫn chỉ qua
/// `ChapterTextNormalizer.normalize` (an toàn đa luồng: `JunkFilterManager` chụp luật dưới lock, `NSRegularExpression`
/// dùng chung được giữa các luồng).
enum AINameScanTextLoader {
    /// Văn bản đã chuẩn hoá của một chương, kèm chỉ số 0-based theo mục lục.
    struct ChapterText: Sendable {
        let index: Int
        let text: String
    }

    /// Kết quả bước đọc: văn bản theo đúng thứ tự chương (đã bỏ chương rỗng) và thời gian từng pha (ms, thời gian thực).
    struct LoadResult: Sendable {
        let texts: [ChapterText]
        let readMs: Int
        let normalizeMs: Int
    }

    private static let chunkSize = 48
    private static let maxNormalizeWidth = 4
    /// Provider API: 5 chương/lượt (cắt 15.000 ký tự lúc gửi — không đổi ở đây).
    private static let apiChaptersPerBatch = 5

    /// Đọc + chuẩn hoá `chapters` theo khối. `onChunkLoaded(k)` báo số chương đã đọc xong sau mỗi khối.
    /// Bị huỷ ⇒ trả `nil` ngay giữa các khối và **không** báo tiến độ nữa.
    static func loadTexts(
        bookId: String,
        chapters: [StoredChapterSnapshot],
        onChunkLoaded: (Int) -> Void
    ) async -> LoadResult? {
        var texts: [ChapterText] = []
        texts.reserveCapacity(chapters.count)
        var readTime: CFAbsoluteTime = 0
        var normalizeTime: CFAbsoluteTime = 0
        var unreadableChapters = 0
        var start = 0
        while start < chapters.count {
            if Task.isCancelled { return nil }
            let chunk = Array(chapters[start..<min(start + chunkSize, chapters.count)])
            let readStart = CFAbsoluteTimeGetCurrent()
            let raws: [String?]
            do {
                raws = try await BookBinManager.shared.readChapterContents(
                    bookId: bookId,
                    ranges: chunk.map { (offset: $0.offset, length: $0.length) }
                )
            } catch {
                // File không có / mở hỏng thì mọi khối sau cũng hỏng ⇒ chỉ log khối đầu tiên, cuối bước log tổng.
                if unreadableChapters == 0 {
                    AppLogger.shared.log("❌ 🤖 [AI] Quét tên riêng: không đọc được ch.\((chunk.first?.index ?? 0) + 1)–ch.\((chunk.last?.index ?? 0) + 1): \(error.localizedDescription)")
                }
                unreadableChapters += chunk.count
                raws = Array(repeating: nil, count: chunk.count)
            }
            let normalizeStart = CFAbsoluteTimeGetCurrent()
            readTime += normalizeStart - readStart
            if Task.isCancelled { return nil }
            let normalized = await normalizeConcurrently(raws)
            normalizeTime += CFAbsoluteTimeGetCurrent() - normalizeStart
            for (chapter, text) in zip(chunk, normalized) {
                guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                texts.append(ChapterText(index: chapter.index, text: text))
            }
            start += chunk.count
            if Task.isCancelled { return nil }
            onChunkLoaded(start)
        }
        if unreadableChapters > chunkSize {
            AppLogger.shared.log("❌ 🤖 [AI] Quét tên riêng: tổng cộng \(unreadableChapters)/\(chapters.count) chương không đọc được")
        }
        return LoadResult(texts: texts, readMs: Int(readTime * 1000), normalizeMs: Int(normalizeTime * 1000))
    }

    /// Chuẩn hoá song song, tối đa `min(maxNormalizeWidth, số lõi đang hoạt động)` việc cùng lúc; kết quả đúng thứ tự.
    private static func normalizeConcurrently(_ raws: [String?]) async -> [String?] {
        let width = max(1, min(maxNormalizeWidth, ProcessInfo.processInfo.activeProcessorCount))
        return await withTaskGroup(of: (Int, String?).self, returning: [String?].self) { group in
            var results = [String?](repeating: nil, count: raws.count)
            var next = 0
            while next < min(width, raws.count) {
                let position = next
                let raw = raws[position]
                group.addTask { (position, raw.map { ChapterTextNormalizer.normalize($0).content }) }
                next += 1
            }
            while let finished = await group.next() {
                results[finished.0] = finished.1
                guard next < raws.count else { continue }
                let nextPosition = next
                let raw = raws[nextPosition]
                group.addTask { (nextPosition, raw.map { ChapterTextNormalizer.normalize($0).content }) }
                next += 1
            }
            return results
        }
    }

    /// Gom văn bản chương thành các lượt, mỗi lượt mang chương đầu/cuối. Ngữ nghĩa chia như trước 1.3.602:
    /// - API: `apiChaptersPerBatch` chương/lượt, nối `"\n\n"`.
    /// - Gemini Web: gom chương liền nhau tới `characterLimit` *Character*, không cắt giữa chương (một chương dài hơn
    ///   mức đó vẫn đứng riêng một lượt). Đếm `text.count` **một** lần mỗi chương rồi cộng dồn — trước đây mỗi vòng gọi
    ///   `current.count` trên cả chuỗi đang gom (O(n) đếm grapheme). `"\n\n"` không bao giờ dính grapheme với chữ hai
    ///   bên nên tổng cộng dồn bằng đúng `count` của chuỗi nối.
    ///
    /// `characterLimit` là đúng mức `extractNamesFromText` cắt lúc gửi (API 15.000, Gemini Web 40.000) ⇒ chương cuối của
    /// lượt (`lastChapterIndex`, dùng cho điểm tiếp nối) là chương cuối nằm **trọn** trong phần thật sự được gửi: lượt API
    /// 5 chương dài bị cắt thì phần đuôi không được tính là đã quét.
    static func makeBatches(_ texts: [ChapterText], isGeminiWeb: Bool, characterLimit: Int) -> [AINameScanFailedBatch] {
        let counts = texts.map { $0.text.count }
        var ranges: [Range<Int>] = []
        if isGeminiWeb {
            var groupStart = 0
            var currentCount = 0
            for position in texts.indices {
                let count = counts[position]
                if position > groupStart, currentCount + count + 2 > characterLimit {
                    ranges.append(groupStart..<position)
                    groupStart = position
                    currentCount = 0
                }
                currentCount += position == groupStart ? count : count + 2
            }
            if groupStart < texts.count { ranges.append(groupStart..<texts.count) }
        } else {
            ranges = stride(from: 0, to: texts.count, by: apiChaptersPerBatch).map { start in
                start..<min(start + apiChaptersPerBatch, texts.count)
            }
        }
        return ranges.enumerated().map { item in
            let range = item.element
            return AINameScanFailedBatch(
                text: texts[range].map(\.text).joined(separator: "\n\n"),
                turnIndex: item.offset + 1,
                totalTurns: ranges.count,
                firstChapterIndex: texts[range.lowerBound].index,
                lastChapterIndex: lastSentChapterIndex(texts, counts: counts, range: range, characterLimit: characterLimit)
            )
        }
    }

    /// Chương cuối của `range` nằm trọn trong `characterLimit` ký tự đầu của chuỗi nối. Chương đầu tự nó đã dài hơn mức
    /// đó thì vẫn tính là chương đó (gửi lại cũng chỉ được ngần ấy), kẻo điểm tiếp nối kẹt mãi ở đây.
    private static func lastSentChapterIndex(
        _ texts: [ChapterText],
        counts: [Int],
        range: Range<Int>,
        characterLimit: Int
    ) -> Int {
        var used = 0
        var last = texts[range.lowerBound].index
        for position in range {
            used += position == range.lowerBound ? counts[position] : counts[position] + 2
            guard used <= characterLimit else { break }
            last = texts[position].index
        }
        return last
    }
}
