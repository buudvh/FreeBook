import Foundation

/// HTML → văn bản thuần theo spec §5.5.2 (cũng là `java.htmlFormat`, §6.4.4).
///
/// 1. `\r\n` → `\n`. 2. Có thẻ: `<br>`, `</p>`, `</div>`, `</h1…6>`, `</li>`, `</tr>` → xuống dòng; bỏ `<script>`/`<style>`
/// cùng nội dung; bỏ mọi thẻ còn lại (ảnh bị bỏ ở đợt 1). 3. Giải thực thể HTML. 4. Trim từng dòng (gồm khoảng trắng
/// toàn góc), bỏ dòng rỗng.
///
/// Kết quả vẫn phải đi qua `ChapterTextNormalizer` của FreeBook (nguồn duy nhất chuẩn hoá văn bản chương).
enum LegadoHTMLText {
    private static let scriptStyle = try? NSRegularExpression(
        pattern: "<(script|style)\\b[^>]*>[\\s\\S]*?</\\1\\s*>", options: [.caseInsensitive]
    )
    private static let lineBreakTags = try? NSRegularExpression(
        pattern: "<br\\s*/?>|</(?:p|div|h[1-6]|li|tr)\\s*>", options: [.caseInsensitive]
    )
    private static let anyTag = try? NSRegularExpression(pattern: "<[^>]*>", options: [])
    private static let entity = try? NSRegularExpression(pattern: "&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z][a-zA-Z0-9]{1,15});", options: [])

    private static let namedEntities: [String: String] = [
        "nbsp": " ", "lt": "<", "gt": ">", "amp": "&", "quot": "\"", "apos": "'",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "lsquo": "\u{2018}", "rsquo": "\u{2019}",
        "hellip": "\u{2026}", "mdash": "\u{2014}", "ndash": "\u{2013}", "middot": "\u{00B7}",
        "emsp": " ", "ensp": " ", "thinsp": " ", "copy": "\u{00A9}", "reg": "\u{00AE}",
        "times": "\u{00D7}", "divide": "\u{00F7}", "laquo": "\u{00AB}", "raquo": "\u{00BB}",
        "bull": "\u{2022}", "deg": "\u{00B0}", "yen": "\u{00A5}", "trade": "\u{2122}"
    ]

    /// Văn bản đã làm sạch: mỗi dòng một đoạn, không dòng rỗng.
    static func plainText(fromHTML html: String) -> String {
        var text = html.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if text.contains("<") {
            text = replace(scriptStyle, in: text, with: "")
            text = replace(lineBreakTags, in: text, with: "\n")
            text = replace(anyTag, in: text, with: "")
        }
        text = decodeEntities(text)
        return text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: lineTrimSet) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Bỏ thẻ và giải thực thể nhưng giữ các dòng (dùng cho `intro`, §5.1.2).
    static func stripTags(_ html: String) -> String {
        plainText(fromHTML: html)
    }

    private static let lineTrimSet: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "\u{3000}\u{00A0}\u{200B}\u{FEFF}")
        return set
    }()

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&"), let regex = entity else { return text }
        let nsText = text as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            output += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let name = nsText.substring(with: match.range(at: 1))
            output += decode(name) ?? nsText.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }
        output += nsText.substring(from: cursor)
        return output
    }

    private static func decode(_ name: String) -> String? {
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
            return UInt32(name.dropFirst(2), radix: 16).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
        }
        if name.hasPrefix("#") {
            return UInt32(name.dropFirst()).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
        }
        return namedEntities[name] ?? namedEntities[name.lowercased()]
    }

    private static func replace(_ regex: NSRegularExpression?, in text: String, with template: String) -> String {
        guard let regex else { return text }
        return LegadoRegexCache.replaceAll(regex, in: text, template: template)
    }
}
