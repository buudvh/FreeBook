import Foundation

/// Lượt 2 của bộ lọc name local trên phần đã đọc — `Snapshot.__init__` của bản thử Python: chỉ xét các ứng viên đủ
/// "Ít nhất N lần" ở lượt 1 (`survivors`), quét lại toàn bộ chữ đã đọc để đếm số lần xuất hiện thật (`occ`) và ngữ cảnh
/// hai bên.
///
/// Chữ bên trái / phải lưu theo đơn vị UTF-16; `0` thay cho `"|"` của Python (đầu / cuối đoạn, hoặc danh xưng đứng sau ở
/// `rightPerson`) — chữ Hán không bao giờ là 0. Dựng mới mỗi lần chụp; không sửa `LocalNameFilterAccumulator`.
final class LocalNameFilterOccurrences {
    /// Chỉ số → cụm; `survivorIndex` chiều ngược lại.
    let survivors: [LocalNameFilterTermKey]
    let survivorIndex: [LocalNameFilterTermKey: Int]
    /// `Snapshot.titles`.
    let titles: Set<LocalNameFilterTermKey>

    private(set) var occurrences: [Int32]
    private(set) var glueLeft: [Int32]
    private(set) var glueSuffix: [Int32]
    private(set) var glueRight: [Int32]
    private(set) var speech: [Int32]
    /// v3 `title_after`: số lần có danh xưng đứng ngay sau.
    private(set) var titleAfter: [Int32]
    private(set) var left: [[UInt16: Int32]]
    private(set) var right: [[UInt16: Int32]]
    /// `right_p`: như `right`, nhưng danh xưng đứng sau (林戎兄) = ranh giới — chỉ dùng khi xét tên người.
    private(set) var rightPerson: [[UInt16: Int32]]

    private let titleMaxLength: Int

    private init(survivors: [LocalNameFilterTermKey], titles: Set<LocalNameFilterTermKey>) {
        self.survivors = survivors
        var index: [LocalNameFilterTermKey: Int] = [:]
        index.reserveCapacity(survivors.count)
        for (position, term) in survivors.enumerated() { index[term] = position }
        survivorIndex = index
        self.titles = titles
        titleMaxLength = titles.map(\.count).max() ?? 0
        let zeros = [Int32](repeating: 0, count: survivors.count)
        occurrences = zeros
        glueLeft = zeros
        glueSuffix = zeros
        glueRight = zeros
        speech = zeros
        titleAfter = zeros
        let empty = [[UInt16: Int32]](repeating: [:], count: survivors.count)
        left = empty
        right = empty
        rightPerson = empty
    }

    /// Chạy lượt 2. `nil` ⇒ task bị huỷ giữa chừng.
    static func scan(
        _ accumulator: LocalNameFilterAccumulator,
        setup: LocalNameFilterSetup,
        dictionaries: LocalNameFilterDictionaries
    ) -> LocalNameFilterOccurrences? {
        let minCount = Int32(setup.minCount)
        let survivors = accumulator.stats.compactMap { $0.value.count >= minCount ? $0.key : nil }
        let result = LocalNameFilterOccurrences(survivors: survivors, titles: accumulator.titles())
        let completed = accumulator.text.withUnsafeBufferPointer { units in
            result.scanRuns(units, accumulator: accumulator, setup: setup, dictionaries: dictionaries)
        }
        return completed ? result : nil
    }

    private func scanRuns(
        _ units: UnsafeBufferPointer<UInt16>,
        accumulator: LocalNameFilterAccumulator,
        setup: LocalNameFilterSetup,
        dictionaries: LocalNameFilterDictionaries
    ) -> Bool {
        let maxLength = survivors.map(\.count).max() ?? 0
        guard maxLength >= 2 else { return !Task.isCancelled }
        // Mọi ứng viên dài ≥ 2 ⇒ vị trí nào hai chữ đầu không là đầu của ứng viên nào thì bỏ qua cả mọi độ dài.
        var startsTerm = [Bool](repeating: false, count: 65_536)
        var prefixPairs = Set<UInt32>()
        for term in survivors {
            startsTerm[Int(term[0])] = true
            prefixPairs.insert(LocalNameFilterRules.pair(term[0], term[1]))
        }
        let runStarts = accumulator.runStarts
        let runEnds = accumulator.runEnds
        for runIndex in runStarts.indices {
            if runIndex & 255 == 0, Task.isCancelled { return false }
            let start = runStarts[runIndex]
            let length = runEnds[runIndex] - start
            guard length >= 2 else { continue }
            for offset in 0..<(length - 1) {
                let first = units[start + offset]
                guard startsTerm[Int(first)],
                      prefixPairs.contains(LocalNameFilterRules.pair(first, units[start + offset + 1])) else { continue }
                for termLength in 2...maxLength {
                    if offset + termLength > length { break }
                    let term = LocalNameFilterTermKey(units, start: start + offset, count: termLength)
                    guard let index = survivorIndex[term] else { continue }
                    observe(index, term: term, units: units, runStart: start, runLength: length, offset: offset,
                            setup: setup, dictionaries: dictionaries)
                }
            }
        }
        return !Task.isCancelled
    }

    /// Thân vòng `for L …` của `Snapshot.__init__` cho một lần xuất hiện của `term` tại `run[offset:offset + L]`.
    private func observe(
        _ index: Int,
        term: LocalNameFilterTermKey,
        units: UnsafeBufferPointer<UInt16>,
        runStart: Int,
        runLength: Int,
        offset: Int,
        setup: LocalNameFilterSetup,
        dictionaries: LocalNameFilterDictionaries
    ) {
        let position = runStart + offset
        occurrences[index] += 1
        if offset > 0, dictionaries.containsVietPhrase(units[position - 1], units[position]) {
            glueLeft[index] += 1
        }
        // Chữ đầu là đuôi của tên chỗ / môn phái đứng trước (昊天宗|宗主).
        if offset > 0, setup.has(term.first, .suffixChar) {
            for back in 1...min(4, offset) {
                let piece = LocalNameFilterTermKey(units, start: position - back, count: back + 1)
                if survivorIndex[piece] != nil || dictionaries.status(piece) == .known {
                    glueSuffix[index] += 1
                    break
                }
            }
        }
        let after = offset + term.count
        // Chữ cuối dính vào chữ sau thành từ / danh xưng (杨源|大长老). Lát `pl = 3` vượt cuối đoạn bị Python cắt còn 2 chữ
        // — trùng lát `pl = 2` nên chỉ xét khi đủ 3 chữ.
        if after < runLength {
            let lastPosition = position + term.count - 1
            if dictionaries.containsVietPhrase(units[lastPosition], units[lastPosition + 1])
                || titles.contains(LocalNameFilterTermKey(units, start: lastPosition, count: 2))
                || (after + 1 < runLength && titles.contains(LocalNameFilterTermKey(units, start: lastPosition, count: 3))) {
                glueRight[index] += 1
            }
        }
        left[index][offset > 0 ? units[position - 1] : 0, default: 0] += 1
        // Danh xưng đứng sau (林戎兄, 庄正哥) = ranh giới, như hết câu. Lát vượt cuối đoạn: Python cắt ngắn rồi so — cùng
        // kết quả với thử từ độ dài còn lại trở xuống (đoạn sau danh xưng khi đó rỗng ở cả hai cách).
        var skip = 0
        var titleLength = min(titleMaxLength, runLength - after)
        while titleLength >= 1 {
            if titles.contains(LocalNameFilterTermKey(units, start: runStart + after, count: titleLength)) {
                skip = titleLength
                break
            }
            titleLength -= 1
        }
        let rightUnit: UInt16 = after >= runLength ? 0 : units[runStart + after]
        right[index][rightUnit, default: 0] += 1
        rightPerson[index][skip > 0 ? 0 : rightUnit, default: 0] += 1
        if skip > 0 { titleAfter[index] += 1 }
        // `any(tail.startswith(p) for p in PERSON_AFTER)` với `tail` = 2 chữ sau tên (sau danh xưng nếu có).
        let tailOffset = after + skip
        if tailOffset < runLength {
            let head = units[runStart + tailOffset]
            if LocalNameFilterRules.has(head, .personAfterSingle)
                || (tailOffset + 1 < runLength
                    && LocalNameFilterRules.personAfterPairs.contains(
                        LocalNameFilterRules.pair(head, units[runStart + tailOffset + 1]))) {
                speech[index] += 1
            }
        }
    }
}
