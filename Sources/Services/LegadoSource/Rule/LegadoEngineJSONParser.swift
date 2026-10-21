import Foundation

/// Parser JSON của engine nguồn Legado, hai chế độ (spec §1.2.1):
///
/// - **chuẩn**: JSON thường; dùng để nhận diện thân phản hồi là JSON. Vẫn chấp nhận ký tự điều khiển thô trong chuỗi
///   (máy chủ thật hay trả như vậy).
/// - **lenient**: thêm nháy đơn, khoá không nháy, giá trị không nháy (giá trị `@put:{k:a.0@href}` là rule), phẩy thừa,
///   chú thích `//` `/* */`; văn bản là nhiều object nối nhau thì lấy object đầu.
///
/// Chạy trên mảng byte UTF-8: mọi dấu phân cách đều là ASCII nên cắt lát không bao giờ rơi giữa ký tự nhiều byte.
struct LegadoEngineJSONParser {
    private let bytes: [UInt8]
    private let lenient: Bool
    private var index = 0
    private var depth = 0

    private static let maxDepth = 400

    /// Trả `nil` khi không parse được (chế độ chuẩn: kể cả khi còn ký tự thừa sau giá trị).
    static func parse(_ text: String, lenient: Bool = false) -> LegadoEngineJSON? {
        var parser = LegadoEngineJSONParser(bytes: Array(text.utf8), lenient: lenient)
        return parser.parseDocument()
    }

    /// Thử nhanh "văn bản có phải JSON object/mảng không" mà không parse khi ký tự đầu không phải `{`/`[`.
    static func parseContainer(_ text: String) -> LegadoEngineJSON? {
        guard let first = text.unicodeScalars.first(where: { !Self.isWhitespaceScalar($0) }),
              first == "{" || first == "[" else { return nil }
        return parse(text, lenient: false)
    }

    private static func isWhitespaceScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\n" || scalar == "\r" || scalar == "\t" || scalar == "\u{FEFF}"
    }

    private init(bytes: [UInt8], lenient: Bool) {
        self.bytes = bytes
        self.lenient = lenient
    }

    // MARK: - Cấu trúc

    private mutating func parseDocument() -> LegadoEngineJSON? {
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { index = 3 }
        skipWhitespace()
        guard let value = parseValue(allowBare: false) else { return nil }
        skipWhitespace()
        if index < bytes.count && !lenient { return nil }
        return value
    }

    private mutating func parseValue(allowBare: Bool) -> LegadoEngineJSON? {
        depth += 1
        defer { depth -= 1 }
        guard depth < Self.maxDepth else { return nil }
        skipWhitespace()
        guard index < bytes.count else { return nil }
        let byte = bytes[index]
        switch byte {
        case Self.openBrace: return parseObject()
        case Self.openBracket: return parseArray()
        case Self.doubleQuote: return parseString(quote: Self.doubleQuote).map { LegadoEngineJSON.string($0) }
        case Self.singleQuote where lenient: return parseString(quote: Self.singleQuote).map { LegadoEngineJSON.string($0) }
        default:
            break
        }
        if lenient, let curly = parseCurlyString() { return .string(curly) }
        if let literal = parseLiteral() { return literal }
        if Self.isNumberStart(byte) || (lenient && (byte == Self.plus || byte == Self.dot)),
           let number = parseNumber() {
            return number
        }
        guard lenient, allowBare else { return nil }
        return parseBareValue()
    }

    private mutating func parseObject() -> LegadoEngineJSON? {
        index += 1
        var entries: [(key: String, value: LegadoEngineJSON)] = []
        while true {
            skipWhitespace()
            guard index < bytes.count else { return lenient ? .object(entries) : nil }
            if bytes[index] == Self.closeBrace {
                index += 1
                return .object(entries)
            }
            if bytes[index] == Self.comma, lenient {
                index += 1
                continue
            }
            guard let key = parseKey() else { return nil }
            skipWhitespace()
            guard index < bytes.count, bytes[index] == Self.colon else { return nil }
            index += 1
            guard let value = parseValue(allowBare: true) else { return nil }
            entries.append((key: key, value: value))
            skipWhitespace()
            guard index < bytes.count else { return lenient ? .object(entries) : nil }
            if bytes[index] == Self.comma {
                index += 1
            } else if bytes[index] != Self.closeBrace {
                return nil
            }
        }
    }

    private mutating func parseArray() -> LegadoEngineJSON? {
        index += 1
        var items: [LegadoEngineJSON] = []
        while true {
            skipWhitespace()
            guard index < bytes.count else { return lenient ? .array(items) : nil }
            if bytes[index] == Self.closeBracket {
                index += 1
                return .array(items)
            }
            if bytes[index] == Self.comma, lenient {
                index += 1
                continue
            }
            guard let value = parseValue(allowBare: true) else { return nil }
            items.append(value)
            skipWhitespace()
            guard index < bytes.count else { return lenient ? .array(items) : nil }
            if bytes[index] == Self.comma {
                index += 1
            } else if bytes[index] != Self.closeBracket {
                return nil
            }
        }
    }

    private mutating func parseKey() -> String? {
        let byte = bytes[index]
        if byte == Self.doubleQuote { return parseString(quote: Self.doubleQuote) }
        guard lenient else { return nil }
        if byte == Self.singleQuote { return parseString(quote: Self.singleQuote) }
        if let curly = parseCurlyString() { return curly }
        let start = index
        while index < bytes.count, bytes[index] != Self.colon,
              bytes[index] != Self.comma, bytes[index] != Self.closeBrace {
            index += 1
        }
        let key = String(decoding: bytes[start..<index], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    /// Giá trị không nháy (chỉ lenient): đọc tới `,` `}` `]` ở mức ngoài cùng, giữ ngoặc và nháy bên trong.
    private mutating func parseBareValue() -> LegadoEngineJSON? {
        let start = index
        var nesting = 0
        var quote: UInt8 = 0
        while index < bytes.count {
            let byte = bytes[index]
            if quote != 0 {
                if byte == Self.backslash { index += 1 } else if byte == quote { quote = 0 }
            } else if byte == Self.doubleQuote || byte == Self.singleQuote {
                quote = byte
            } else if byte == Self.openBracket || byte == Self.openParen || byte == Self.openBrace {
                nesting += 1
            } else if byte == Self.closeBracket || byte == Self.closeParen || byte == Self.closeBrace {
                if nesting == 0 { break }
                nesting -= 1
            } else if byte == Self.comma && nesting == 0 {
                break
            }
            index += 1
        }
        let end = min(index, bytes.count)
        let text = String(decoding: bytes[start..<end], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : .string(text)
    }

    // MARK: - Giá trị đơn

    private mutating func parseLiteral() -> LegadoEngineJSON? {
        for (word, value) in Self.literals where matches(word) {
            let next = index + word.count
            if next < bytes.count, Self.isIdentifierByte(bytes[next]) { continue }
            index = next
            return value
        }
        return nil
    }

    private func matches(_ word: [UInt8]) -> Bool {
        guard index + word.count <= bytes.count else { return false }
        for offset in 0..<word.count where bytes[index + offset] != word[offset] {
            return false
        }
        return true
    }

    private mutating func parseNumber() -> LegadoEngineJSON? {
        let start = index
        while index < bytes.count, Self.isNumberByte(bytes[index]) {
            index += 1
        }
        let raw = String(decoding: bytes[start..<index], as: UTF8.self)
        // Số chỉ là tiền tố của một giá trị không nháy (`12abc`) ⇒ để parser đọc như giá trị trần.
        if lenient, index < bytes.count, Self.isIdentifierByte(bytes[index]) {
            index = start
            return nil
        }
        guard let value = Double(raw) else {
            index = start
            return nil
        }
        return .number(value, raw.hasPrefix("+") ? String(raw.dropFirst()) : raw)
    }

    private mutating func parseString(quote: UInt8) -> String? {
        index += 1
        var buffer: [UInt8] = []
        while index < bytes.count {
            let byte = bytes[index]
            if byte == quote {
                index += 1
                return String(decoding: buffer, as: UTF8.self)
            }
            if byte == Self.backslash {
                index += 1
                guard index < bytes.count else { break }
                appendEscape(into: &buffer)
                continue
            }
            buffer.append(byte)
            index += 1
        }
        return lenient ? String(decoding: buffer, as: UTF8.self) : nil
    }

    /// Chuỗi trong nháy cong `“…”` / `‘…’` (chỉ lenient, đính chính §15.3 mục 5a: `',{webView:“true”}'`). Không bắt
    /// đầu bằng nháy cong ⇒ `nil` và không đổi vị trí đọc.
    private mutating func parseCurlyString() -> String? {
        guard index + 2 < bytes.count, bytes[index] == 0xE2, bytes[index + 1] == 0x80 else { return nil }
        let closers: [UInt8]
        switch bytes[index + 2] {
        case 0x9C: closers = [0x9D, 0x9C]
        case 0x98: closers = [0x99, 0x98]
        default: return nil
        }
        index += 3
        var buffer: [UInt8] = []
        while index < bytes.count {
            if index + 2 < bytes.count, bytes[index] == 0xE2, bytes[index + 1] == 0x80, closers.contains(bytes[index + 2]) {
                index += 3
                return String(decoding: buffer, as: UTF8.self)
            }
            buffer.append(bytes[index])
            index += 1
        }
        return String(decoding: buffer, as: UTF8.self)
    }

    private mutating func appendEscape(into buffer: inout [UInt8]) {
        let byte = bytes[index]
        index += 1
        switch byte {
        case UInt8(ascii: "n"): buffer.append(0x0A)
        case UInt8(ascii: "r"): buffer.append(0x0D)
        case UInt8(ascii: "t"): buffer.append(0x09)
        case UInt8(ascii: "b"): buffer.append(0x08)
        case UInt8(ascii: "f"): buffer.append(0x0C)
        case UInt8(ascii: "u"):
            guard let high = readHex4() else { buffer.append(UInt8(ascii: "u")); return }
            var scalarValue = high
            if (0xD800...0xDBFF).contains(high), index + 1 < bytes.count,
               bytes[index] == Self.backslash, bytes[index + 1] == UInt8(ascii: "u") {
                let saved = index
                index += 2
                if let low = readHex4(), (0xDC00...0xDFFF).contains(low) {
                    scalarValue = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
                } else {
                    index = saved
                }
            }
            let scalar = Unicode.Scalar(scalarValue) ?? "\u{FFFD}"
            buffer.append(contentsOf: Array(String(Character(scalar)).utf8))
        default:
            // `\"`, `\\`, `\/`, `\'` và escape lạ: giữ ký tự sau dấu `\`.
            buffer.append(byte)
        }
    }

    private mutating func readHex4() -> UInt32? {
        guard index + 4 <= bytes.count else { return nil }
        let text = String(decoding: bytes[index..<(index + 4)], as: UTF8.self)
        guard let value = UInt32(text, radix: 16) else { return nil }
        index += 4
        return value
    }

    // MARK: - Khoảng trắng & chú thích

    private mutating func skipWhitespace() {
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 {
                index += 1
            } else if byte == 0xEF, index + 2 < bytes.count, bytes[index + 1] == 0xBB, bytes[index + 2] == 0xBF {
                index += 3
            } else if lenient, byte == Self.slash, index + 1 < bytes.count, bytes[index + 1] == Self.slash {
                while index < bytes.count, bytes[index] != 0x0A { index += 1 }
            } else if lenient, byte == Self.slash, index + 1 < bytes.count, bytes[index + 1] == Self.star {
                index += 2
                while index + 1 < bytes.count, !(bytes[index] == Self.star && bytes[index + 1] == Self.slash) {
                    index += 1
                }
                index = min(index + 2, bytes.count)
            } else if lenient, byte < 0x20 {
                index += 1
            } else {
                return
            }
        }
    }

    // MARK: - Bảng byte

    private static let openBrace = UInt8(ascii: "{")
    private static let closeBrace = UInt8(ascii: "}")
    private static let openBracket = UInt8(ascii: "[")
    private static let closeBracket = UInt8(ascii: "]")
    private static let openParen = UInt8(ascii: "(")
    private static let closeParen = UInt8(ascii: ")")
    private static let doubleQuote = UInt8(ascii: "\"")
    private static let singleQuote = UInt8(ascii: "'")
    private static let backslash = UInt8(ascii: "\\")
    private static let slash = UInt8(ascii: "/")
    private static let star = UInt8(ascii: "*")
    private static let comma = UInt8(ascii: ",")
    private static let colon = UInt8(ascii: ":")
    private static let plus = UInt8(ascii: "+")
    private static let dot = UInt8(ascii: ".")

    private static let literals: [([UInt8], LegadoEngineJSON)] = [
        (Array("true".utf8), .bool(true)),
        (Array("false".utf8), .bool(false)),
        (Array("null".utf8), .null)
    ]

    private static func isNumberStart(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "-") || (byte >= 48 && byte <= 57)
    }

    private static func isNumberByte(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57) || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "+")
            || byte == UInt8(ascii: ".") || byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E")
    }

    private static func isIdentifierByte(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
            || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "$") || byte >= 0x80
    }
}
