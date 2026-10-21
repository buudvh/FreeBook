import Foundation

/// Đọc JSON của dữ liệu nguồn Legado theo kiểu **khoan dung** (spec §1.1, §1.2.1).
///
/// Thứ tự: JSON chuẩn (`JSONSerialization`) → parser kiểu JSON5 (nháy đơn, khoá không nháy, phẩy thừa, chú thích
/// `//` `/* */`, ký tự điều khiển và xuống dòng thô trong chuỗi). Văn bản là nhiều giá trị nối nhau ⇒ lấy giá trị
/// **đầu**. Vẫn lỗi ⇒ `nil` (caller coi như rỗng).
///
/// Kết quả cùng kiểu Foundation với `JSONSerialization`: `[String: Any]`, `[Any]`, `String`, `NSNumber` (bool là
/// `NSNumber(value: Bool)`), `NSNull`. Thuần, không state — gọi được từ thread bất kỳ. Engine dùng lại được cho
/// header, option URL, `@put` (cùng mục spec).
public enum LegadoModelJSON {
    /// Số lớp "chuỗi JSON chứa JSON" tối đa được bóc (spec §1.1: văn bản bị escape hai lần).
    public static let maxStringLayers = 2

    /// JSON chuẩn trước, rồi lenient. `nil` khi cả hai đều không đọc được.
    public static func parse(_ text: String) -> Any? {
        let cleaned = stripBOM(text)
        if let data = cleaned.data(using: .utf8),
           let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return value
        }
        var parser = LenientParser(scalars: Array(cleaned.unicodeScalars))
        return parser.parseDocument()
    }

    public static func parseObject(_ text: String) -> [String: Any]? {
        parse(text) as? [String: Any]
    }

    public static func parseArray(_ text: String) -> [Any]? {
        parse(text) as? [Any]
    }

    /// Giải mã `Data` (UTF-8, có thể có BOM) rồi bóc tối đa `maxStringLayers` lớp chuỗi JSON lồng.
    public static func parseDocument(data: Data) -> Any? {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        var value: Any?
        if let strict = try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed]) {
            value = strict
        } else {
            let text = String(decoding: bytes, as: UTF8.self)
            value = parse(text)
        }
        var layers = 0
        while let wrapped = value as? String, layers < maxStringLayers {
            layers += 1
            value = parse(wrapped)
        }
        return value
    }

    public static func stripBOM(_ text: String) -> String {
        guard let first = text.unicodeScalars.first, first.value == 0xFEFF else { return text }
        return String(String.UnicodeScalarView(text.unicodeScalars.dropFirst()))
    }

    /// Bytes JSON **ổn định** (khoá sắp xếp, không escape `/`) — dùng để ghi `source.json` và so "giống hệt".
    public static func serialize(_ object: Any) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// Như `serialize` nhưng trả chuỗi; dùng khi đổi object/mảng con sang chuỗi (spec §1.2).
    public static func serializedString(_ object: Any) -> String? {
        serialize(object).map { String(decoding: $0, as: UTF8.self) }
    }

    // MARK: - Parser khoan dung

    private struct LenientParser {
        let scalars: [Unicode.Scalar]
        var index = 0
        var depth = 0

        static let maxDepth = 256

        init(scalars: [Unicode.Scalar]) {
            self.scalars = scalars
        }

        mutating func parseDocument() -> Any? {
            skipTrivia()
            guard index < scalars.count else { return nil }
            // Ký tự thừa sau giá trị đầu bị bỏ qua: `{…},\n{…}` ⇒ object đầu (spec §1.2.1 bước 3).
            return parseValue()
        }

        mutating func parseValue() -> Any? {
            skipTrivia()
            guard index < scalars.count else { return nil }
            let c = scalars[index]
            if c == "{" { return parseObject() }
            if c == "[" { return parseArray() }
            if c == "\"" || c == "'" { return parseString(quote: c) }
            return parseBareWord()
        }

        mutating func parseObject() -> Any? {
            guard depth < Self.maxDepth else { return nil }
            depth += 1
            defer { depth -= 1 }
            index += 1
            var result: [String: Any] = [:]
            while true {
                skipTrivia()
                guard index < scalars.count else { return nil }
                let c = scalars[index]
                if c == "}" {
                    index += 1
                    return result
                }
                if c == "," {
                    index += 1
                    continue
                }
                guard let key = parseKey() else { return nil }
                skipTrivia()
                guard index < scalars.count, scalars[index] == ":" else { return nil }
                index += 1
                guard let value = parseValue() else { return nil }
                result[key] = value
            }
        }

        mutating func parseArray() -> Any? {
            guard depth < Self.maxDepth else { return nil }
            depth += 1
            defer { depth -= 1 }
            index += 1
            var result: [Any] = []
            while true {
                skipTrivia()
                guard index < scalars.count else { return nil }
                let c = scalars[index]
                if c == "]" {
                    index += 1
                    return result
                }
                if c == "," {
                    index += 1
                    continue
                }
                guard let value = parseValue() else { return nil }
                result.append(value)
            }
        }

        mutating func parseKey() -> String? {
            guard index < scalars.count else { return nil }
            let c = scalars[index]
            if c == "\"" || c == "'" { return parseString(quote: c) }
            let token = readToken(stopAtColon: true)
            return token.isEmpty ? nil : token
        }

        mutating func parseString(quote: Unicode.Scalar) -> String? {
            index += 1
            var out = String.UnicodeScalarView()
            while index < scalars.count {
                let c = scalars[index]
                index += 1
                if c == quote { return String(out) }
                guard c == "\\" else {
                    out.append(c)
                    continue
                }
                guard index < scalars.count else { return nil }
                let escaped = scalars[index]
                index += 1
                switch escaped {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "b": out.append(Unicode.Scalar(UInt8(8)))
                case "f": out.append(Unicode.Scalar(UInt8(12)))
                case "0": out.append(Unicode.Scalar(UInt8(0)))
                case "\n": break // nối dòng kiểu JSON5
                case "u": appendUnicodeEscape(into: &out)
                case "x":
                    if let code = readHex(count: 2), let scalar = Unicode.Scalar(code) {
                        out.append(scalar)
                    } else {
                        out.append(escaped)
                    }
                default: out.append(escaped) // \" \' \\ \/ và escape lạ ⇒ chính ký tự đó
                }
            }
            return nil // chuỗi không đóng nháy
        }

        mutating func appendUnicodeEscape(into out: inout String.UnicodeScalarView) {
            guard let code = readHex(count: 4) else {
                out.append("u")
                return
            }
            if code >= 0xD800, code <= 0xDBFF,
               index + 1 < scalars.count, scalars[index] == "\\", scalars[index + 1] == "u" {
                let saved = index
                index += 2
                if let low = readHex(count: 4), low >= 0xDC00, low <= 0xDFFF {
                    let combined = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    out.append(Unicode.Scalar(combined) ?? "\u{FFFD}")
                    return
                }
                index = saved
            }
            out.append(Unicode.Scalar(code) ?? "\u{FFFD}")
        }

        mutating func readHex(count: Int) -> UInt32? {
            guard index + count <= scalars.count else { return nil }
            var value: UInt32 = 0
            for offset in 0..<count {
                guard let digit = Self.hexValue(scalars[index + offset]) else { return nil }
                value = value * 16 + digit
            }
            index += count
            return value
        }

        /// Giá trị không nháy: `true`/`false`/`null`/`undefined`, số, còn lại là chuỗi trần.
        mutating func parseBareWord() -> Any? {
            let token = readToken(stopAtColon: false)
            guard !token.isEmpty else { return nil }
            switch token {
            case "true": return NSNumber(value: true)
            case "false": return NSNumber(value: false)
            case "null", "undefined": return NSNull()
            default: break
            }
            if let integer = Int64(token) { return NSNumber(value: integer) }
            let lower = token.lowercased()
            if lower.hasPrefix("0x"), let hex = Int64(lower.dropFirst(2), radix: 16) { return NSNumber(value: hex) }
            if let double = Double(token), double.isFinite { return NSNumber(value: double) }
            return token
        }

        mutating func readToken(stopAtColon: Bool) -> String {
            var out = String.UnicodeScalarView()
            while index < scalars.count {
                let c = scalars[index]
                if Self.isTrivia(c) || c == "," || c == "}" || c == "]" || c == "{" || c == "[" { break }
                if stopAtColon && c == ":" { break }
                out.append(c)
                index += 1
            }
            return String(out)
        }

        mutating func skipTrivia() {
            while index < scalars.count {
                let c = scalars[index]
                if Self.isTrivia(c) {
                    index += 1
                    continue
                }
                guard c == "/", index + 1 < scalars.count else { return }
                let next = scalars[index + 1]
                if next == "/" {
                    index += 2
                    while index < scalars.count, scalars[index] != "\n" { index += 1 }
                } else if next == "*" {
                    index += 2
                    while index + 1 < scalars.count, !(scalars[index] == "*" && scalars[index + 1] == "/") { index += 1 }
                    index = min(index + 2, scalars.count)
                } else {
                    return
                }
            }
        }

        /// Khoảng trắng, ký tự điều khiển (vd `\x00` ngoài chuỗi), BOM, NBSP.
        static func isTrivia(_ c: Unicode.Scalar) -> Bool {
            c.value <= 0x20 || c.value == 0xFEFF || c.value == 0xA0 || c.value == 0x3000
        }

        static func hexValue(_ c: Unicode.Scalar) -> UInt32? {
            switch c.value {
            case 48...57: return c.value - 48
            case 65...70: return c.value - 55
            case 97...102: return c.value - 87
            default: return nil
            }
        }
    }
}
