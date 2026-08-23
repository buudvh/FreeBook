import Foundation
import SwiftSoup

/// Bóc text thuần và ranh giới đoạn/chương ra khỏi HTML–XHTML.
///
/// Dùng chung cho cả ba đường HTML, EPUB và MOBI (MOBI sau khi giải nén cũng là HTML), nên mọi cải
/// thiện chất lượng text chỉ cần sửa ở đây.
///
/// **Không** dùng `String.cleanHTML()`: hàm đó không loại nội dung `<script>/<style>` và không tách
/// biên `<p>/<h1>/<li>` nên tất cả đoạn dính thành một dòng. `cleanHTML()` giữ nguyên cho caller cũ.
enum XhtmlTextExtractor {
    /// Một khúc nội dung tách theo heading. `title == nil` ⇒ phần nằm trước heading đầu tiên.
    struct Section: Sendable {
        let title: String?
        let text: String
    }

    /// Chuỗi mốc chèn vào HTML tại biên khối. `SwiftSoup.text()` gộp mọi whitespace thành một dấu
    /// cách nên không thể chèn `\n` trực tiếp; mốc dạng chữ thì sống sót qua cả parse lẫn `text()`.
    private static let blockMarker = "@@FBNL@@"

    private static let blockTags = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6",
        "li", "blockquote", "pre", "tr", "section", "article"
    ]

    // MARK: - Text thuần

    static func plainText(html: String) -> String {
        let marked = insertBlockMarkers(html)
        guard let doc = try? SwiftSoup.parse(marked) else {
            return recompose(stripTags(marked))
        }
        _ = try? doc.select("script, style").remove()
        let raw = (try? doc.text()) ?? ""
        return recompose(raw)
    }

    /// Text một dòng (dùng cho tiêu đề chương lấy từ heading hoặc `<title>`).
    static func inlineText(html: String) -> String {
        return plainText(html: html)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func insertBlockMarkers(_ html: String) -> String {
        var result = html
        for tag in blockTags {
            result = result.replacingOccurrences(
                of: "</\(tag)>",
                with: "\(blockMarker)</\(tag)>",
                options: [.caseInsensitive]
            )
        }
        result = result.replacingOccurrences(of: "<br", with: "\(blockMarker)<br", options: [.caseInsensitive])
        return result
    }

    /// Đổi mốc thành newline, trim từng dòng, gộp mọi khoảng trắng dài thành tối đa một dòng trống.
    private static func recompose(_ raw: String) -> String {
        let lines = raw
            .replacingOccurrences(of: blockMarker, with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var output: [String] = []
        for line in lines {
            if line.isEmpty {
                if output.last?.isEmpty == false {
                    output.append("")
                }
            } else {
                output.append(line)
            }
        }
        while output.last?.isEmpty == true { output.removeLast() }
        while output.first?.isEmpty == true { output.removeFirst() }
        return output.joined(separator: "\n")
    }

    /// Dự phòng khi SwiftSoup không parse được: bỏ tag bằng regex và giải mã vài entity phổ biến.
    private static func stripTags(_ html: String) -> String {
        var text = html.replacingOccurrences(
            of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, replacement) in [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")
        ] {
            text = text.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        return text
    }

    // MARK: - Tách theo heading

    /// Tách tài liệu theo mức heading đầu tiên (h1 → h3) cho ra **≥ 2** khúc.
    /// `nil` khi không có mức nào đủ 2 heading — caller rơi về quy tắc TOC.
    static func headingSections(html: String) -> [Section]? {
        for level in ["h1", "h2", "h3"] {
            guard let regex = try? NSRegularExpression(
                pattern: "<\(level)\\b[^>]*>([\\s\\S]*?)</\(level)>",
                options: [.caseInsensitive]
            ) else { continue }

            let ns = html as NSString
            let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
            guard matches.count >= 2 else { continue }

            var sections: [Section] = []
            let prefaceLength = matches[0].range.location
            if prefaceLength > 0 {
                let preface = plainText(html: ns.substring(with: NSRange(location: 0, length: prefaceLength)))
                if !preface.isEmpty {
                    sections.append(Section(title: nil, text: preface))
                }
            }

            for (index, match) in matches.enumerated() {
                let bodyStart = match.range.location + match.range.length
                let bodyEnd = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
                let bodyHtml = bodyEnd > bodyStart
                    ? ns.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
                    : ""
                let title = inlineText(html: ns.substring(with: match.range(at: 1)))
                sections.append(Section(title: title, text: plainText(html: bodyHtml)))
            }
            return sections
        }
        return nil
    }

    /// Tiêu đề đầu tiên tìm được trong một tài liệu (h1 → h6, rồi `<title>`).
    static func firstHeading(html: String) -> String? {
        return firstTagText(html: html, tags: ["h1", "h2", "h3", "h4", "h5", "h6", "title"])
    }

    /// Nội dung text của tag đầu tiên khớp, thử lần lượt theo `tags`.
    static func firstTagText(html: String, tags: [String]) -> String? {
        for tag in tags {
            guard let regex = try? NSRegularExpression(
                pattern: "<\(tag)\\b[^>]*>([\\s\\S]*?)</\(tag)>",
                options: [.caseInsensitive]
            ) else { continue }
            let ns = html as NSString
            guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { continue }
            let title = inlineText(html: ns.substring(with: match.range(at: 1)))
            if !title.isEmpty { return title }
        }
        return nil
    }

    /// `src` của `<img>` đầu tiên, giữ nguyên dạng tương đối (caller tự giải theo thư mục của mình).
    static func firstImageSrc(html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<(?:img|image)\\b[^>]*?(?:src|xlink:href)\\s*=\\s*[\"']([^\"']+)[\"']",
            options: [.caseInsensitive]
        ) else { return nil }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let src = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return src.isEmpty ? nil : src
    }

    /// Bỏ dòng đầu nếu nó trùng tiêu đề — heading vừa nằm trong text nên sẽ lặp lại ở thân chương.
    static func dropLeadingTitle(_ text: String, title: String) -> String {
        var lines = text.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeFirst()
        }
        if let first = lines.first, first.trimmingCharacters(in: .whitespacesAndNewlines) == title {
            lines.removeFirst()
        }
        while let first = lines.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Cắt theo id neo (EPUB có mục lục trỏ `part1.xhtml#ch3`)
    /// Cắt một tài liệu thành nhiều đoạn theo danh sách `id` neo, trả về map `id` → text.
    /// `id` không tìm thấy sẽ không có trong kết quả.
    static func anchorSegments(html: String, anchorIds: [String]) -> [String: String] {
        let ns = html as NSString
        var marks: [(location: Int, id: String)] = []

        for id in Set(anchorIds) {
            var found: Int?
            for quote in ["\"", "'"] {
                let needle = "id=\(quote)\(id)\(quote)"
                let range = ns.range(of: needle, options: [.caseInsensitive])
                if range.location != NSNotFound {
                    found = range.location
                    break
                }
            }
            guard let attributeLocation = found else { continue }
            // Lùi về dấu `<` mở tag chứa attribute để không cắt giữa tag.
            let tagRange = ns.range(
                of: "<",
                options: [.backwards],
                range: NSRange(location: 0, length: attributeLocation)
            )
            guard tagRange.location != NSNotFound else { continue }
            marks.append((location: tagRange.location, id: id))
        }

        guard !marks.isEmpty else { return [:] }
        marks.sort { $0.location < $1.location }

        var result: [String: String] = [:]
        for (index, mark) in marks.enumerated() {
            let end = index + 1 < marks.count ? marks[index + 1].location : ns.length
            guard end > mark.location else { continue }
            let fragment = ns.substring(with: NSRange(location: mark.location, length: end - mark.location))
            result[mark.id] = plainText(html: fragment)
        }
        return result
    }

    // MARK: - Bảng mã khai báo trong file

    /// Đọc `charset` / `encoding` khai trong 2 KB đầu (`<meta charset>`, `http-equiv`, `<?xml encoding=…?>`).
    static func declaredCharsetName(in data: Data) -> String? {
        let headLength = min(2048, data.count)
        let head = data.subdata(in: data.startIndex..<(data.startIndex + headLength))
        guard let text = String(data: head, encoding: .isoLatin1) else { return nil }
        for pattern in ["charset\\s*=\\s*[\"']?([A-Za-z0-9_\\-]+)", "encoding\\s*=\\s*[\"']?([A-Za-z0-9_\\-]+)"] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let ns = text as NSString
            guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { continue }
            return ns.substring(with: match.range(at: 1))
        }
        return nil
    }
}
