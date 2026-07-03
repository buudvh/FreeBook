import Foundation

extension String {
    /// Loại bỏ các thẻ HTML và giải mã thực thể HTML để trả về văn bản sạch.
    public func cleanHTML() -> String {
        var text = self
        
        // 1. Thay thế các thẻ xuống dòng/đoạn bằng ký tự \n
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</?p\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</?div\\s*>", with: "\n", options: .regularExpression)
        
        // 2. Loại bỏ tất cả các thẻ HTML khác
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
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
        text = text.replacingOccurrences(of: "[\t ]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n\n+", with: "\n\n", options: .regularExpression)
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func decodeNumericEntities(_ string: String) -> String {
        var result = string
        guard let regex = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);", options: []) else {
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
