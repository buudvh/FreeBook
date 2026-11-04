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
                relativeBranch(part.trimmingCharacters(in: .whitespaces))
            }.joined(separator: " | ")
        }
        return relativeBranch(trimmed)
    }

    /// `/x…` ⇒ `./x…`. `//X[p]…` ⇒ `(self::X[p]… | .//X[p]…)`: chính mục cũng khớp bước đầu (spec §2.12) — 耽美小说
    /// `bookList //h2` + `name //h2/a//text()`, mục là `<h2>` nên `.//h2/a` không ra gì. Chỉ khi bước đầu là phép thử tên
    /// phần tử (`h2`, `p:x`, `*`) và không có vị từ chỉ số (`[1]`, `last()`, `position()` — trên trục `self` vị từ chỉ số đổi
    /// nghĩa); `//@x`, `//text()`, trục tường minh giữ `.//…` (`.//@x` đã gồm thuộc tính của chính mục).
    private static func relativeBranch(_ piece: String) -> String {
        guard piece.hasPrefix("/") else { return piece }
        let descendant = "." + piece
        guard piece.hasPrefix("//"), let selfBranch = selfStep(String(piece.dropFirst(2))) else { return descendant }
        return "(" + selfBranch + " | " + descendant + ")"
    }

    /// `X[p]rest` ⇒ `self::X[p]rest`; `nil` khi bước đầu không phải tên phần tử hoặc có vị từ chỉ số.
    private static func selfStep(_ path: String) -> String? {
        let characters = Array(path)
        var index = 0
        while index < characters.count, isNameCharacter(characters[index]) { index += 1 }
        let name = String(characters[0..<index])
        guard !name.isEmpty, !name.contains("::"), !name.hasPrefix("."), !name.hasPrefix("-"),
              name.first.map({ !$0.isNumber }) ?? false else { return nil }
        // Vị từ của bước đầu.
        while index < characters.count, characters[index] == "[" {
            guard let end = predicateEnd(characters, from: index) else { return nil }
            let predicate = String(characters[(index + 1)..<(end - 1)])
            if isPositional(predicate) { return nil }
            index = end
        }
        // Sau bước đầu chỉ được là hết biểu thức hoặc bước kế (`/…`); `(` = hàm/phép thử nút, chữ khác = toán tử.
        guard index == characters.count || characters[index] == "/" else { return nil }
        // Phần sau phải là đường dẫn thuần: `//span/text()='VIP'` là biểu thức so sánh — hợp hai giá trị bool là lỗi XPath.
        guard isPlainPath(characters, from: index) else { return nil }
        return "self::" + path
    }

    /// Không có toán tử (`=`, `!`, `<`, `>`, `+`, `,`) hay khoảng trắng (`and`/`or`/`div`/`mod`) ở mức ngoài cùng.
    private static func isPlainPath(_ characters: [Character], from start: Int) -> Bool {
        var depth = 0
        var quote: Character?
        for character in characters[start...] {
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == "[" || character == "(" {
                depth += 1
            } else if character == "]" || character == ")" {
                depth -= 1
            } else if depth == 0, character.isWhitespace || "=!<>+,".contains(character) {
                return false
            }
        }
        return true
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-" || character == "."
            || character == ":" || character == "*"
    }

    /// Vị trí ngay sau `]` cân với `[` tại `start` (bỏ qua chuỗi nháy).
    private static func predicateEnd(_ characters: [Character], from start: Int) -> Int? {
        var depth = 0
        var quote: Character?
        var index = start
        while index < characters.count {
            let character = characters[index]
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
                if depth == 0 { return index + 1 }
            }
            index += 1
        }
        return nil
    }

    /// Vị từ chỉ số: số (`[2]`, `[ 1 ]`) hoặc có `position()` / `last()`.
    private static func isPositional(_ predicate: String) -> Bool {
        let trimmed = predicate.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed.allSatisfy({ $0.isNumber || $0 == "." }) { return true }
        return predicate.contains("position()") || predicate.contains("last()")
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
