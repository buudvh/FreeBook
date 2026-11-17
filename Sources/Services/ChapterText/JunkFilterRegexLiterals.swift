import Foundation

/// Rút **ký tự literal bắt buộc** của một regex lọc rác (1.3.970): mọi chuỗi regex khớp đều phải chứa từng ký tự này
/// (ICU khớp đúng mã, options `[]`, không cờ nội tuyến) ⇒ chữ chương thiếu một ký tự thì `replaceMatches` vốn ra 0 chỗ.
///
/// Cố ý bảo thủ — gặp cú pháp không chắc thì trả rỗng (quy tắc luôn chạy như cũ):
/// - chỉ xét tầng ngoài cùng; nội dung nhóm `(...)` và lớp `[...]` coi như một atom không bắt buộc ký tự nào;
/// - `|` ở tầng ngoài, `\Q`, nhóm `(?` không phải `(?:` `(?=` `(?!` `(?>` `(?<=` `(?<!` `(?<tên>` (cờ `(?i)`, `(?x)`,
///   chú thích `(?#`…), escape chữ / số ngoài danh sách atom (`\p{…}`, `\x…`, `\u…`, `\1`…), `{` không phải lượng từ
///   hợp lệ, `)` `]` `}` lẻ ⇒ bỏ cuộc;
/// - literal theo sau `?`, `*`, `{0…}` là tuỳ chọn ⇒ không bắt buộc.
enum JunkFilterRegexLiterals {
    /// `\` + ký tự này ở tầng ngoài = đúng ký tự đó (ICU: `\` trước ký tự không phải chữ / số là trích literal).
    private static let quotedLiterals = Set("\\^$.|?*+()[]{}/-_:;,!\"'#%&=@~ ".unicodeScalars)
    /// Escape một chữ cái không kéo theo tham số — atom (lớp ký tự / neo / ký tự điều khiển), không bắt buộc literal.
    private static let atomEscapes = Set("dDwWsSbBnrtfaeRhHvVXAZzG".unicodeScalars)

    static func requiredScalars(in pattern: String) -> [Unicode.Scalar] {
        let scalars = Array(pattern.unicodeScalars)
        guard hasOnlySupportedGroups(scalars) else { return [] }
        return parseTopLevel(scalars) ?? []
    }

    private static func hasOnlySupportedGroups(_ s: [Unicode.Scalar]) -> Bool {
        for index in s.indices {
            if s[index] == "\\", index + 1 < s.count, s[index + 1] == "Q" { return false }
            guard s[index] == "(", index + 1 < s.count, s[index + 1] == "?" else { continue }
            guard index + 2 < s.count else { return false }
            switch s[index + 2] {
            case ":", "=", "!", ">":
                continue
            case "<":
                guard index + 3 < s.count else { return false }
                let next = s[index + 3]
                let isName = next.isASCII && next.properties.isAlphabetic
                guard next == "=" || next == "!" || isName else { return false }
            default:
                return false
            }
        }
        return true
    }

    private static func parseTopLevel(_ s: [Unicode.Scalar]) -> [Unicode.Scalar]? {
        var required: [Unicode.Scalar] = []
        var pending: Unicode.Scalar? // literal vừa đọc, chờ xem có lượng từ cho phép 0 lần không
        var hasAtom = false
        var index = 0
        func commitPending() {
            if let pending { required.append(pending) }
            pending = nil
        }
        while index < s.count {
            let scalar = s[index]
            switch scalar {
            case "\\":
                guard index + 1 < s.count else { return nil }
                let next = s[index + 1]
                commitPending()
                if quotedLiterals.contains(next) {
                    pending = next
                } else if !atomEscapes.contains(next) {
                    return nil
                }
                hasAtom = true
                index += 2
            case "(":
                commitPending()
                guard let end = skipGroup(s, from: index) else { return nil }
                hasAtom = true
                index = end
            case "[":
                commitPending()
                guard let end = skipClass(s, from: index) else { return nil }
                hasAtom = true
                index = end
            case "*", "?", "+", "{":
                guard hasAtom else { return nil }
                let minimum: Int
                if scalar == "{" {
                    guard let interval = parseInterval(s, from: index) else { return nil }
                    minimum = interval.minimum
                    index = interval.end
                } else {
                    minimum = scalar == "+" ? 1 : 0
                    index += 1
                }
                if minimum == 0 { pending = nil } else { commitPending() }
                if index < s.count, s[index] == "?" || s[index] == "+" { index += 1 } // lười / chiếm hữu
                hasAtom = false
            case ".", "^", "$":
                commitPending()
                hasAtom = true
                index += 1
            case "|", ")", "]", "}":
                return nil
            default:
                commitPending()
                pending = scalar
                hasAtom = true
                index += 1
            }
        }
        commitPending()
        return required
    }

    /// `s[start] == "("` ⇒ chỉ số ngay sau `)` khớp; `nil` nếu không đóng.
    private static func skipGroup(_ s: [Unicode.Scalar], from start: Int) -> Int? {
        var depth = 0
        var index = start
        while index < s.count {
            switch s[index] {
            case "\\":
                index += 2
            case "[":
                guard let end = skipClass(s, from: index) else { return nil }
                index = end
            case "(":
                depth += 1
                index += 1
            case ")":
                depth -= 1
                index += 1
                if depth == 0 { return index }
            default:
                index += 1
            }
        }
        return nil
    }

    /// `s[start] == "["` ⇒ chỉ số ngay sau `]` khớp (lớp lồng `[[a-z]&&[^b]]`, `[[:alpha:]]` tính độ sâu); `]` đứng đầu
    /// lớp (`[]…]`, `[^]…]`) mơ hồ ⇒ `nil`.
    private static func skipClass(_ s: [Unicode.Scalar], from start: Int) -> Int? {
        var depth = 0
        var index = start
        while index < s.count {
            switch s[index] {
            case "\\":
                index += 2
            case "[":
                depth += 1
                index += 1
                if index < s.count, s[index] == "^" { index += 1 }
                if index < s.count, s[index] == "]" { return nil }
            case "]":
                depth -= 1
                index += 1
                if depth == 0 { return index }
            default:
                index += 1
            }
        }
        return nil
    }

    /// `{n}`, `{n,}`, `{n,m}` ⇒ (n, chỉ số sau `}`); dạng khác ⇒ `nil`.
    private static func parseInterval(_ s: [Unicode.Scalar], from start: Int) -> (minimum: Int, end: Int)? {
        var index = start + 1
        var minimum = 0
        var digits = 0
        while index < s.count, let value = digitValue(s[index]) {
            minimum = minimum * 10 + value
            digits += 1
            index += 1
            guard digits <= 6 else { return nil }
        }
        guard digits > 0, index < s.count else { return nil }
        if s[index] == "," {
            index += 1
            while index < s.count, digitValue(s[index]) != nil { index += 1 }
        }
        guard index < s.count, s[index] == "}" else { return nil }
        return (minimum, index + 1)
    }

    private static func digitValue(_ scalar: Unicode.Scalar) -> Int? {
        guard ("0"..."9").contains(scalar) else { return nil }
        return Int(scalar.value - 48)
    }
}
