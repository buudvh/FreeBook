import Foundation

/// Một phần tử XPath (mục của rule danh sách XPath, spec §2.12).
///
/// Giữ tham chiếu **mạnh** tới `LegadoXPathDocument`: con trỏ `xmlNodePtr` thuộc về document, document được giải
/// phóng (`xmlFreeDoc`) trước nút là con trỏ treo. Chỉ dùng trên thread engine đã tạo nó.
final class LegadoXPathNode {
    let document: LegadoXPathDocument
    let pointer: xmlNodePtr

    init(document: LegadoXPathDocument, pointer: xmlNodePtr) {
        self.document = document
        self.pointer = pointer
    }

    /// Chữ của nút gồm con cháu (`getString` trên phần tử, §2.12 / U26).
    var textContent: String {
        LegadoXPathDocument.content(of: pointer)
    }

    /// HTML của nút, để rule con không phải XPath parse lại bằng SwiftSoup.
    var outerHTML: String {
        document.serialize(pointer)
    }

    var tagName: String {
        LegadoXPathDocument.name(of: pointer)
    }

    /// XPath với nút này làm ngữ cảnh. `//x` và `/x` được hiểu **tương đối** với mục (`.//x`, `./x`): mỗi mục danh
    /// sách độc lập, nếu chạy tuyệt đối thì mục nào cũng trả kết quả của cả trang.
    func evaluate(_ expression: String) -> [LegadoXPathDocument.Item] {
        document.evaluate(Self.relative(expression), at: pointer)
    }

    static func relative(_ expression: String) -> String {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return trimmed }
        // Biểu thức hợp `a | b`: tương đối hoá từng vế.
        if trimmed.contains("|") {
            return splitUnion(trimmed).map { part -> String in
                let piece = part.trimmingCharacters(in: .whitespaces)
                return piece.hasPrefix("/") ? "." + piece : piece
            }.joined(separator: " | ")
        }
        return "." + trimmed
    }

    /// Tách `|` ở mức ngoài cùng (không trong `[...]`, `(...)` hay chuỗi nháy).
    private static func splitUnion(_ expression: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for character in expression {
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == "[" || character == "(" {
                depth += 1
            } else if character == "]" || character == ")" {
                depth -= 1
            } else if character == "|" && depth == 0 {
                parts.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        parts.append(current)
        return parts
    }
}
