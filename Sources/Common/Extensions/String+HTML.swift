import Foundation

extension String {
    /// Loại bỏ các thẻ HTML và giải mã thực thể HTML để trả về văn bản sạch.
    public func cleanHTML() -> String {
        var text = self
        
        // 1. Thay thế các thẻ xuống dòng/đoạn bằng ký tự \n
        text = Self.replaceMatches(Self.brTagRegex, in: text, with: "\n")
        text = Self.replaceMatches(Self.paragraphTagRegex, in: text, with: "\n")
        text = Self.replaceMatches(Self.divTagRegex, in: text, with: "\n")
        
        // 2. Loại bỏ tất cả các thẻ HTML khác
        text = Self.replaceMatches(Self.anyTagRegex, in: text, with: "")
        
        // 3. Giải mã các thực thể HTML phổ biến
        let entities = [
            "&nbsp;": " ",
            "&lt;": "<",
            "&gt;": ">",
            "&amp;": "&",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&ldquo;": "“",
            "&rdquo;": "”",
            "&bdquo;": "„",
            "&lsquo;": "‘",
            "&rsquo;": "’",
            "&hellip;": "...",
            "&ndash;": "–",
            "&mdash;": "—"
        ]
        
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        
        // 4. Giải mã các thực thể unicode dạng số (như &#123; hoặc &#x1a;)
        text = decodeNumericEntities(text)
        
        // 5. Chuẩn hóa khoảng trắng và dòng trống liên tiếp
        text = Self.replaceMatches(Self.horizontalSpaceRegex, in: text, with: " ")
        text = Self.replaceMatches(Self.blankLinesRegex, in: text, with: "\n\n")
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Regex biên dịch một lần, giữ nguyên pattern + cờ inline của bản `replacingOccurrences(options: .regularExpression)` cũ.
    private static let brTagRegex = try? NSRegularExpression(pattern: "(?i)<br\\s*/?>", options: [])
    private static let paragraphTagRegex = try? NSRegularExpression(pattern: "(?i)</?p\\s*>", options: [])
    private static let divTagRegex = try? NSRegularExpression(pattern: "(?i)</?div\\s*>", options: [])
    private static let anyTagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: [])
    private static let horizontalSpaceRegex = try? NSRegularExpression(pattern: "[\t ]+", options: [])
    private static let blankLinesRegex = try? NSRegularExpression(pattern: "\n\n+", options: [])
    private static let numericEntityRegex = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);", options: [])

    /// Template ở đây không chứa `$` hay `\`, nên kết quả trùng `replacingOccurrences(options: .regularExpression)`.
    private static func replaceMatches(_ regex: NSRegularExpression?, in text: String, with template: String) -> String {
        guard let regex else { return text }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private func decodeNumericEntities(_ string: String) -> String {
        var result = string
        guard let regex = Self.numericEntityRegex else {
            return string
        }
        
        let matches = regex.matches(in: string, options: [], range: NSRange(location: 0, length: string.utf16.count))
        
        // Duyệt ngược từ dưới lên để không làm lệch index của các match phía trước
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let entityToken = String(result[range])
            
            let numberPart = entityToken.dropFirst(2).dropLast()
            var codePoint: UInt32? = nil
            
            if numberPart.hasPrefix("x") || numberPart.hasPrefix("X") {
                let hexStr = numberPart.dropFirst()
                codePoint = UInt32(hexStr, radix: 16)
            } else {
                codePoint = UInt32(numberPart, radix: 10)
            }
            
            if let cp = codePoint, let scalar = UnicodeScalar(cp) {
                result.replaceSubrange(range, with: String(scalar))
            }
        }
        
        return result
    }
}
