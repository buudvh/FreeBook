import Foundation

/// Tách một tài liệu HTML (trang truyện đã lưu, hoặc khối HTML giải nén từ MOBI) thành chương.
///
/// Thứ tự rơi, dừng ở nhánh đầu tiên cho ra ≥ 2 chương:
/// 1. mốc `<mbp:pagebreak>` — MOBI do Calibre sinh đặt đúng một mốc mỗi chương;
/// 2. heading `h1`–`h3`;
/// 3. quy tắc TOC trên text thuần (đúng đường TXT đang chạy);
/// 4. giữ một chương (sách ngắn hợp lệ).
enum HtmlBookParser {
    static func parse(
        html: String,
        fileName: String,
        rules: [TOCRule]? = nil,
        structure: BookImportService.StructureMode = .auto
    ) -> ParsedBook {
        let bookTitle = documentTitle(html: html) ?? TxtBookParser.bookTitle(fromFileName: fileName)
        let cover = firstAbsoluteImageUrl(html: html)

        if structure != .tocRules {
            if let chapters = pagebreakChapters(html: html), chapters.count >= 2 {
                return ParsedBook(
                    title: bookTitle,
                    chapters: chapters,
                    remoteCoverUrl: cover,
                    structureNote: "Mốc trang trong file — \(chapters.count) chương"
                )
            }
            if let chapters = headingChapters(html: html), chapters.count >= 2 {
                return ParsedBook(
                    title: bookTitle,
                    chapters: chapters,
                    remoteCoverUrl: cover,
                    structureNote: "Tiêu đề HTML — \(chapters.count) chương"
                )
            }
        }

        let text = XhtmlTextExtractor.plainText(html: html)
        let byRules = TxtBookParser.parse(content: text, fileName: fileName, rules: rules).chapters
        if byRules.count >= 2 {
            return ParsedBook(
                title: bookTitle,
                chapters: byRules,
                remoteCoverUrl: cover,
                structureNote: "Quy tắc TOC — \(byRules.count) chương"
            )
        }

        guard !text.isEmpty else {
            return ParsedBook(title: bookTitle, chapters: [], remoteCoverUrl: cover)
        }
        return ParsedBook(
            title: bookTitle,
            chapters: [ParserChapter(title: bookTitle, content: text)],
            remoteCoverUrl: cover,
            structureNote: "Không tìm thấy ranh giới chương — giữ 1 chương"
        )
    }

    // MARK: - Các nhánh tách chương

    private static func pagebreakChapters(html: String) -> [ParserChapter]? {
        guard let regex = try? NSRegularExpression(
            pattern: "<mbp:pagebreak[^>]*>",
            options: [.caseInsensitive]
        ) else { return nil }

        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 1 else { return nil }

        var bounds: [Int] = [0]
        for match in matches {
            bounds.append(match.range.location + match.range.length)
        }
        bounds.append(ns.length)

        var chapters: [ParserChapter] = []
        for index in 0..<(bounds.count - 1) {
            let start = bounds[index]
            let end = bounds[index + 1]
            guard end > start else { continue }
            let fragment = ns.substring(with: NSRange(location: start, length: end - start))
            let text = XhtmlTextExtractor.plainText(html: fragment)
            guard !text.isEmpty else { continue }
            let title = XhtmlTextExtractor.firstHeading(html: fragment) ?? firstLineTitle(text)
            chapters.append(ParserChapter(
                title: title,
                content: XhtmlTextExtractor.dropLeadingTitle(text, title: title)
            ))
        }
        return chapters.isEmpty ? nil : chapters
    }

    private static func headingChapters(html: String) -> [ParserChapter]? {
        guard let sections = XhtmlTextExtractor.headingSections(html: html) else { return nil }
        var chapters: [ParserChapter] = []
        for section in sections {
            let title = section.title ?? "Mở đầu"
            // Bỏ khúc rỗng: heading trang trí (tên sách, tên tác giả) không có nội dung theo sau.
            guard !section.text.isEmpty else { continue }
            chapters.append(ParserChapter(title: title, content: section.text))
        }
        return chapters.isEmpty ? nil : chapters
    }

    // MARK: - Metadata

    private static func documentTitle(html: String) -> String? {
        // `<title>` trước `<h1>`: khi tài liệu tách chương bằng `h1` thì `h1` đầu tiên là tên chương,
        // không phải tên truyện.
        return XhtmlTextExtractor.firstTagText(html: html, tags: ["title", "h1"])
    }

    /// Ảnh bìa: `<img>` đầu tiên có `src` tuyệt đối `http(s)`. Ảnh tương đối bị bỏ vì picker
    /// `asCopy: true` chỉ copy đúng một file, không có file ảnh nằm cạnh.
    private static func firstAbsoluteImageUrl(html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<img[^>]+src\\s*=\\s*[\"'](https?://[^\"']+)[\"']",
            options: [.caseInsensitive]
        ) else { return nil }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    // MARK: - Tiêu đề suy ra từ text

    private static func firstLineTitle(_ text: String) -> String {
        let first = text
            .components(separatedBy: "\n")
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return "Chương" }
        return trimmed
    }
}
