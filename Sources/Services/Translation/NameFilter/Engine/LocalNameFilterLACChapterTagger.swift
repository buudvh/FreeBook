import Foundation

/// Gắn nhãn LAC cho một khối chương của lượt lọc name local — bước 1 của `lacpipe.py`, chạy **song song theo chương**
/// (tối đa số nhân − 1 việc cùng lúc, giữ một nhân cho giao diện). Mỗi dòng của chương gọi `LACTagging.tag` **đúng một
/// lần**; kết quả mỗi chương là số đếm thuần (`Chapter`), cộng vào `LocalNameFilterLACCounts` theo thứ tự chương ở task
/// của lượt lọc.
///
/// Dòng như Python: tách theo xuống dòng, bỏ khoảng trắng hai đầu, bỏ dòng rỗng và dòng tên chương (`第N章`). Dòng không
/// có chữ Hán (U+3400–9FFF, U+F900–FAFF) không gọi model — không thể sinh từ được đếm.
enum LocalNameFilterLACChapterTagger {
    struct Chapter: Sendable {
        /// Từ ≥ 2 chữ có chữ Hán, LAC gắn nhãn thực thể → số lần theo nhóm.
        let entities: [LocalNameFilterWord: LocalNameFilterLACCounts.Tally]
        /// Từ ≥ 2 chữ có chữ Hán, LAC gắn nhãn **không** phải thực thể (`n`, `v`, `m`…) → số lần — luật (e) và luật phân
        /// loại L2 / L4 (plan 2026-11-27-phan-loai-name) so với số lần nhãn thực thể của đúng từ đó.
        let others: [LocalNameFilterWord: Int32]
        /// Các dòng có chữ Hán, nối bằng `\n` (UTF-16).
        let text: [UInt16]
        let taggedLines: Int
    }

    /// Kết quả đúng thứ tự `texts`; chương `nil` (đọc hỏng) ⇒ `nil`. Cả khối ⇒ `nil` khi task bị huỷ.
    static func tag(_ texts: [String?], tagger: any LACTagging) async -> [Chapter?]? {
        let width = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        let results = await withTaskGroup(of: (Int, Chapter?).self, returning: [Chapter?].self) { group in
            var results = [Chapter?](repeating: nil, count: texts.count)
            var next = 0
            while next < min(width, texts.count) {
                let position = next
                let text = texts[position]
                group.addTask {
                    (position, text.flatMap { tagChapter($0, tagger: tagger) })
                }
                next += 1
            }
            while let finished = await group.next() {
                results[finished.0] = finished.1
                guard next < texts.count, !Task.isCancelled else { continue }
                let position = next
                let text = texts[position]
                group.addTask {
                    (position, text.flatMap { tagChapter($0, tagger: tagger) })
                }
                next += 1
            }
            return results
        }
        return Task.isCancelled ? nil : results
    }

    /// Một chương; `nil` khi task bị huỷ giữa chừng (xét mỗi 32 dòng).
    static func tagChapter(_ text: String, tagger: any LACTagging) -> Chapter? {
        var entities: [LocalNameFilterWord: LocalNameFilterLACCounts.Tally] = [:]
        var others: [LocalNameFilterWord: Int32] = [:]
        var joined: [UInt16] = []
        var taggedLines = 0
        let lines = text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" })
        for rawLine in lines {
            if isChapterHeading(rawLine) { continue }
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, line.unicodeScalars.contains(where: { LocalNameFilterRules.isLACHan($0.value) }) else {
                continue
            }
            taggedLines += 1
            if taggedLines & 31 == 0, Task.isCancelled { return nil }
            if !joined.isEmpty { joined.append(0x0A) }
            joined.append(contentsOf: line.utf16)
            for token in tagger.tag(line) {
                let word = LocalNameFilterWord(token.text)
                guard word.count >= 2, word.scalars.contains(where: LocalNameFilterRules.isLACHan) else { continue }
                if let category = LocalNameFilterLACCounts.Tally.category(ofTag: token.tag) {
                    entities[word, default: LocalNameFilterLACCounts.Tally()][category] += 1
                } else {
                    others[word, default: 0] += 1
                }
            }
        }
        return Chapter(entities: entities, others: others, text: joined, taggedLines: taggedLines)
    }

    /// Chữ chương cho **bộ luật** (`LocalNameFilterEngine.feed`), như `split_chapters` của Python: bỏ dòng tên chương
    /// (`第N章…`) — nội dung chương trong app hiếm khi có, nhưng có thì số lần / mảnh / `dict_common_head` của bộ luật lệch
    /// bản tham chiếu (phía LAC đã bỏ ở `tag`). Không có dòng nào bị bỏ ⇒ trả nguyên chuỗi.
    static func removingChapterHeadings(_ text: String) -> String {
        guard text.contains("第") else { return text }
        var kept: [Substring] = []
        var removed = false
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            if isChapterHeading(line) {
                removed = true
            } else {
                kept.append(line)
            }
        }
        return removed ? kept.joined(separator: "\n") : text
    }

    /// `CHAPTER_LINE` của Python trên dòng **chưa** bỏ khoảng trắng: `^\s?第[0-9零一二三四五六七八九十百千两]+章`.
    static func isChapterHeading(_ line: Substring) -> Bool {
        var scalars = line.unicodeScalars[...]
        if let first = scalars.first, first.properties.isWhitespace { scalars = scalars.dropFirst() }
        guard scalars.first == "第" else { return false }
        scalars = scalars.dropFirst()
        var numerals = 0
        while let scalar = scalars.first, chapterNumerals.contains(scalar) {
            numerals += 1
            scalars = scalars.dropFirst()
        }
        return numerals > 0 && scalars.first == "章"
    }

    private static let chapterNumerals = Set("0123456789零一二三四五六七八九十百千两".unicodeScalars)
}
