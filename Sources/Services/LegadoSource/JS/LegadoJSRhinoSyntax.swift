import Foundation

/// Sửa lỗi cú pháp mà Rhino (bản Android) chấp nhận còn JavaScriptCore từ chối (spec §6.1, "Tương thích Rhino"). Chỉ
/// biến đổi văn bản, giữ nguyên số dòng; runtime phân tích lại (không chạy) để lấy lỗi đầu rồi gọi `fix` từng lỗi một.
///
/// - **Ký tự định dạng** (Unicode Cf: U+200B, U+200C, U+200D, U+2060…) nằm ngoài chuỗi, template và regex literal ⇒ bỏ,
///   như ES3 §7.1 bỏ chúng trước khi phân tích từ vựng (`source.getSource\u200b()`). Trong literal thì giữ.
/// - **`let X` trùng tên tham số** của hàm (lỗi sớm của ES2015 `Cannot declare a let variable twice`) ⇒ đổi **một** chỗ
///   `let X` ở dòng báo lỗi (hoặc gần nhất) thành `var X`, như Rhino coi `let` ở thân hàm (`var` trùng tham số giữ giá trị
///   tham số: `let sourceUrl = sourceUrl || "…"`). `const` không bao giờ bị đụng.
///
/// Bộ quét từ vựng là bản rút gọn: nhận chuỗi, chú thích, template (cả `${…}` lồng) và regex literal theo token đứng
/// trước `/` (sau tên/số/`)`/`]`/`}` là phép chia, trừ từ khoá như `return`). Nhầm ở trường hợp hiếm chỉ làm bản sửa
/// không ăn; nó chỉ chạy trên mã **đã** lỗi cú pháp nên không làm hỏng nguồn đang chạy được.
enum LegadoJSRhinoSyntax {
    private static let letTwiceMarker = "Cannot declare a let variable twice: '"
    private static let invalidCharacterMarker = "Invalid character"

    /// Thông báo lỗi có thuộc loại `fix` xử lý không (lọc nhanh trước khi phân tích lại).
    static func isFixable(_ message: String) -> Bool {
        message.hasPrefix("SyntaxError") && (message.contains(letTwiceMarker) || message.contains(invalidCharacterMarker))
    }

    /// Mã đã sửa cho **một** lỗi cú pháp (`line` tính từ 1, 0 = không rõ); không sửa được ⇒ `nil`.
    static func fix(_ code: String, message: String, line: Int) -> String? {
        if let name = quoted(after: letTwiceMarker, in: message) {
            return replacingLet(named: name, near: line, in: code)
        }
        if let character = invalidCharacter(in: message), character.properties.generalCategory == .format {
            return strippingFormatCharacters(code)
        }
        return nil
    }

    // MARK: - Đọc thông báo lỗi

    /// Đoạn giữa hai dấu `'` ngay sau `marker` (`… twice: 'key'.` ⇒ `key`).
    private static func quoted(after marker: String, in message: String) -> String? {
        guard let start = message.range(of: marker)?.upperBound,
              let end = message[start...].firstIndex(of: "'"), end > start else { return nil }
        return String(message[start..<end])
    }

    /// Ký tự bị báo trong `Invalid character '\u200b'` (dạng escape) hoặc `Invalid character: '#'` (nguyên văn).
    private static func invalidCharacter(in message: String) -> Unicode.Scalar? {
        guard let marker = message.range(of: invalidCharacterMarker),
              let open = message[marker.upperBound...].firstIndex(of: "'") else { return nil }
        let rest = message[message.index(after: open)...]
        if rest.hasPrefix("\\u"), let value = UInt32(rest.dropFirst(2).prefix(4), radix: 16) {
            return Unicode.Scalar(value)
        }
        guard let close = rest.firstIndex(of: "'") else { return nil }
        let scalars = rest[..<close].unicodeScalars
        return scalars.count == 1 ? scalars.first : nil
    }

    // MARK: - Biến đổi

    /// Bỏ ký tự Cf ở mã và chú thích; không có gì để bỏ ⇒ `nil`.
    static func strippingFormatCharacters(_ code: String) -> String? {
        let scalars = Array(code.unicodeScalars)
        let kinds = regions(of: scalars)
        var output = String.UnicodeScalarView()
        var removed = false
        for (index, scalar) in scalars.enumerated() {
            if kinds[index] != .literal, scalar.properties.generalCategory == .format {
                removed = true
                continue
            }
            output.append(scalar)
        }
        return removed ? String(output) : nil
    }

    /// Đổi **một** `let <name>` (trong mã, không trong chuỗi/chú thích) thành `var <name>`: chỗ đầu ở dòng `line`, không có
    /// thì ở dòng gần nhất (cách đều thì chỗ đứng trước). Không có ⇒ `nil`.
    static func replacingLet(named name: String, near line: Int, in code: String) -> String? {
        let scalars = Array(code.unicodeScalars)
        let kinds = regions(of: scalars)
        let target = Array(name.unicodeScalars)
        guard !target.isEmpty else { return nil }
        var best: (index: Int, distance: Int)?
        var currentLine = 1
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if isLineTerminator(scalar) {
                if !(scalar == "\r" && index + 1 < scalars.count && scalars[index + 1] == "\n") { currentLine += 1 }
            } else if kinds[index] == .code, isLetDeclaration(at: index, of: target, in: scalars, kinds: kinds) {
                let distance = line > 0 ? abs(currentLine - line) : 0
                if distance < (best?.distance ?? Int.max) { best = (index, distance) }
                if distance == 0 { break }
            }
            index += 1
        }
        guard let chosen = best?.index else { return nil }
        var output = String.UnicodeScalarView()
        output.append(contentsOf: scalars[..<chosen])
        output.append(contentsOf: "var".unicodeScalars)
        output.append(contentsOf: scalars[(chosen + 3)...])
        return String(output)
    }

    /// `let` (cả từ, ở mã) + khoảng trắng + đúng `target` (cả từ).
    private static func isLetDeclaration(at index: Int, of target: [Unicode.Scalar], in scalars: [Unicode.Scalar],
                                         kinds: [Region]) -> Bool {
        guard index + 3 < scalars.count, scalars[index] == "l", scalars[index + 1] == "e", scalars[index + 2] == "t" else {
            return false
        }
        if index > 0, isIdentifierPart(scalars[index - 1]) || scalars[index - 1] == "." { return false }
        var cursor = index + 3
        guard isWhitespace(scalars[cursor]) else { return false }
        while cursor < scalars.count, isWhitespace(scalars[cursor]) { cursor += 1 }
        guard cursor + target.count <= scalars.count, kinds[cursor] == .code,
              Array(scalars[cursor..<(cursor + target.count)]) == target else { return false }
        let after = cursor + target.count
        return after == scalars.count || !isIdentifierPart(scalars[after])
    }

    // MARK: - Quét từ vựng

    private enum Region: UInt8 {
        case code
        case comment
        /// Bên trong chuỗi, template (phần chữ, kể cả dấu `` ` ``, `${`, `}`) hoặc regex literal.
        case literal
    }

    /// Từ khoá mà sau nó `/` mở regex literal (không phải phép chia).
    private static let keywordsBeforeExpression: Set<String> = [
        "return", "typeof", "instanceof", "in", "of", "new", "delete", "void", "throw", "case", "do", "else", "yield", "await"
    ]

    /// Vùng của từng Unicode scalar trong `scalars`.
    private static func regions(of scalars: [Unicode.Scalar]) -> [Region] {
        var kinds = [Region](repeating: .code, count: scalars.count)
        let count = scalars.count
        var index = 0
        var braceDepth = 0
        /// Độ sâu `{` lúc mở mỗi `${` đang dở (template lồng nhau).
        var substitutionDepths: [Int] = []
        var regexAllowed = true
        func mark(_ range: Range<Int>, _ kind: Region) {
            for position in range where position < count { kinds[position] = kind }
        }
        /// Phần chữ của template từ `start` (sau `` ` `` hoặc `}` đóng `${`): tới `` ` `` đóng hoặc `${` mở.
        func scanTemplateText(from start: Int) -> (end: Int, opensSubstitution: Bool) {
            var cursor = start
            while cursor < count {
                let scalar = scalars[cursor]
                if scalar == "\\" { cursor += 2; continue }
                if scalar == "`" { return (cursor + 1, false) }
                if scalar == "$", cursor + 1 < count, scalars[cursor + 1] == "{" { return (cursor + 2, true) }
                cursor += 1
            }
            return (count, false)
        }
        while index < count {
            let scalar = scalars[index]
            let next: Unicode.Scalar? = index + 1 < count ? scalars[index + 1] : nil
            if scalar == "/", next == "/" {
                var end = index
                while end < count, !isLineTerminator(scalars[end]) { end += 1 }
                mark(index..<end, .comment)
                index = end
                continue
            }
            if scalar == "/", next == "*" {
                var end = index + 2
                while end < count, !(scalars[end] == "*" && end + 1 < count && scalars[end + 1] == "/") { end += 1 }
                end = min(end + 2, count)
                mark(index..<end, .comment)
                index = end
                continue
            }
            switch scalar {
            case "\"", "'":
                var end = index + 1
                while end < count {
                    let current = scalars[end]
                    if current == "\\" { end += 2; continue }
                    if current == scalar { end += 1; break }
                    if current == "\n" || current == "\r" { break }
                    end += 1
                }
                mark(index..<end, .literal)
                index = min(end, count)
                regexAllowed = false
            case "`":
                let text = scanTemplateText(from: index + 1)
                mark(index..<text.end, .literal)
                if text.opensSubstitution { substitutionDepths.append(braceDepth) }
                regexAllowed = text.opensSubstitution
                index = text.end
            case "{":
                braceDepth += 1
                regexAllowed = true
                index += 1
            case "}":
                if let depth = substitutionDepths.last, depth == braceDepth {
                    substitutionDepths.removeLast()
                    let text = scanTemplateText(from: index + 1)
                    mark(index..<text.end, .literal)
                    if text.opensSubstitution { substitutionDepths.append(braceDepth) }
                    regexAllowed = text.opensSubstitution
                    index = text.end
                } else {
                    braceDepth -= 1
                    regexAllowed = false
                    index += 1
                }
            case "/":
                if regexAllowed, let end = regexLiteralEnd(from: index, in: scalars) {
                    mark(index..<end, .literal)
                    index = end
                    regexAllowed = false
                } else {
                    regexAllowed = true
                    index += 1
                }
            case ")", "]":
                regexAllowed = false
                index += 1
            default:
                if isIdentifierPart(scalar) {
                    var end = index + 1
                    while end < count, isIdentifierPart(scalars[end]) { end += 1 }
                    let isNumber = ("0"..."9").contains(scalar)
                    let word = end - index <= 10 ? String(String.UnicodeScalarView(scalars[index..<end])) : ""
                    regexAllowed = !isNumber && keywordsBeforeExpression.contains(word)
                    index = end
                } else {
                    if !isWhitespace(scalar), scalar.properties.generalCategory != .format { regexAllowed = true }
                    index += 1
                }
            }
        }
        return kinds
    }

    /// Vị trí ngay sau regex literal mở ở `start` (gồm cờ `gimsuy`); xuống dòng trước `/` đóng ⇒ không phải regex.
    private static func regexLiteralEnd(from start: Int, in scalars: [Unicode.Scalar]) -> Int? {
        var cursor = start + 1
        var inClass = false
        while cursor < scalars.count {
            let scalar = scalars[cursor]
            if isLineTerminator(scalar) { return nil }
            if scalar == "\\" {
                cursor += 2
                continue
            }
            if scalar == "[" {
                inClass = true
            } else if scalar == "]" {
                inClass = false
            } else if scalar == "/", !inClass {
                cursor += 1
                while cursor < scalars.count, isIdentifierPart(scalars[cursor]) { cursor += 1 }
                return cursor
            }
            cursor += 1
        }
        return nil
    }

    private static func isLineTerminator(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\n" || scalar == "\r" || scalar == "\u{2028}" || scalar == "\u{2029}"
    }

    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        isLineTerminator(scalar) || scalar.properties.isWhitespace
    }

    /// Ký tự của tên/số: ASCII chữ, số, `_`, `$`; mọi ký tự ngoài ASCII trừ khoảng trắng và Cf.
    private static func isIdentifierPart(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9", "_", "$": return true
        default: break
        }
        if scalar.isASCII { return false }
        return !scalar.properties.isWhitespace && scalar.properties.generalCategory != .format
    }
}
