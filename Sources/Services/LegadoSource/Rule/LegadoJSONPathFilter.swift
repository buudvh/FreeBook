import Foundation

/// Biểu thức filter `[?(…)]` của JSONPath (spec §2.11.2): `@.x` (tồn tại), `==` `!=` `<` `<=` `>` `>=`, `=~ /re/i`,
/// `in [..]`, `nin [..]`, `&&` `||` `!`, ngoặc, hằng số/chuỗi/`true`/`false`/`null`, đường dẫn `@…`/`$…`.
///
/// Parse một lần khi dựng; biểu thức lỗi cú pháp thì không mục nào khớp.
struct LegadoJSONPathFilter {
    indirect enum Node {
        case path(String)
        case literal(LegadoEngineJSON)
        case regex(NSRegularExpression?)
        case list([LegadoEngineJSON])
        case not(Node)
        case and(Node, Node)
        case or(Node, Node)
        case compare(String, Node, Node)
    }

    private let root: Node?

    init(_ expression: String) {
        var parser = Parser(bytes: Array(expression.utf8))
        let node = parser.parseOr()
        parser.skipSpaces()
        root = parser.failed || parser.index < parser.bytes.count ? nil : node
    }

    func matches(_ value: LegadoEngineJSON, root documentRoot: LegadoEngineJSON) -> Bool {
        guard let node = root else { return false }
        return Self.truth(node, current: value, root: documentRoot)
    }

    // MARK: - Đánh giá

    private static func truth(_ node: Node, current: LegadoEngineJSON, root: LegadoEngineJSON) -> Bool {
        switch node {
        case .not(let inner): return !truth(inner, current: current, root: root)
        case .and(let lhs, let rhs): return truth(lhs, current: current, root: root) && truth(rhs, current: current, root: root)
        case .or(let lhs, let rhs): return truth(lhs, current: current, root: root) || truth(rhs, current: current, root: root)
        case .path(let path):
            return !LegadoJSONPathEvaluator.evaluate(path, on: current, root: root).values.isEmpty
        case .literal(let value):
            switch value {
            case .bool(let flag): return flag
            case .null: return false
            default: return true
            }
        case .regex, .list:
            return true
        case .compare(let op, let lhs, let rhs):
            return compare(op, lhs, rhs, current: current, root: root)
        }
    }

    private static func values(_ node: Node, current: LegadoEngineJSON, root: LegadoEngineJSON) -> [LegadoEngineJSON] {
        switch node {
        case .path(let path): return LegadoJSONPathEvaluator.evaluate(path, on: current, root: root).values
        case .literal(let value): return [value]
        case .list(let items): return items
        default: return [.bool(truth(node, current: current, root: root))]
        }
    }

    private static func compare(_ op: String, _ lhs: Node, _ rhs: Node,
                                current: LegadoEngineJSON, root: LegadoEngineJSON) -> Bool {
        let left = values(lhs, current: current, root: root)
        if op == "=~" {
            guard case .regex(let maybeRegex) = rhs, let regex = maybeRegex, let first = left.first else { return false }
            let text = first.scalarString
            return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        let right = values(rhs, current: current, root: root)
        if op == "in" || op == "nin" {
            guard let first = left.first else { return op == "nin" }
            let found = right.contains { equal(first, $0) }
            return op == "in" ? found : !found
        }
        guard let a = left.first, let b = right.first else {
            return op == "!=" || op == "!=="
        }
        switch op {
        case "==", "===": return equal(a, b)
        case "!=", "!==": return !equal(a, b)
        case "<", "<=", ">", ">=":
            let ordering: Int
            if let x = number(a), let y = number(b) {
                ordering = x < y ? -1 : (x > y ? 1 : 0)
            } else {
                let x = a.scalarString, y = b.scalarString
                ordering = x < y ? -1 : (x > y ? 1 : 0)
            }
            switch op {
            case "<": return ordering < 0
            case "<=": return ordering <= 0
            case ">": return ordering > 0
            default: return ordering >= 0
            }
        default:
            return false
        }
    }

    private static func number(_ value: LegadoEngineJSON) -> Double? {
        if case .number(let number, _) = value { return number }
        if case .string(let text) = value { return Double(text) }
        return nil
    }

    /// So lỏng: số so theo giá trị, kiểu khác nhau so theo chuỗi (`"1" == 1`).
    private static func equal(_ a: LegadoEngineJSON, _ b: LegadoEngineJSON) -> Bool {
        switch (a, b) {
        case (.null, .null): return true
        case (.null, _), (_, .null): return false
        case (.bool(let x), .bool(let y)): return x == y
        case (.number(let x, _), .number(let y, _)): return x == y
        default: return a.scalarString == b.scalarString
        }
    }

    // MARK: - Parser

    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        var failed = false

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func skipSpaces() {
            while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x09 || bytes[index] == 0x0A {
                index += 1
            }
        }

        mutating func parseOr() -> Node {
            var node = parseAnd()
            while consume("||") { node = .or(node, parseAnd()) }
            return node
        }

        mutating func parseAnd() -> Node {
            var node = parseUnary()
            while consume("&&") { node = .and(node, parseUnary()) }
            return node
        }

        mutating func parseUnary() -> Node {
            skipSpaces()
            if index < bytes.count, bytes[index] == UInt8(ascii: "!"),
               !(index + 1 < bytes.count && bytes[index + 1] == UInt8(ascii: "=")) {
                index += 1
                return .not(parseUnary())
            }
            let lhs = parseOperand()
            for op in ["===", "!==", "==", "!=", "<=", ">=", "=~", "<", ">", " in ", " nin "] {
                if consume(op) {
                    let rhs = parseOperand()
                    return .compare(op.trimmingCharacters(in: .whitespaces), lhs, rhs)
                }
            }
            return lhs
        }

        mutating func parseOperand() -> Node {
            skipSpaces()
            guard index < bytes.count else { failed = true; return .literal(.null) }
            let byte = bytes[index]
            if byte == UInt8(ascii: "(") {
                index += 1
                let inner = parseOr()
                if !consume(")") { failed = true }
                return inner
            }
            if byte == UInt8(ascii: "@") || byte == UInt8(ascii: "$") { return .path(readPath()) }
            if byte == UInt8(ascii: "'") || byte == UInt8(ascii: "\"") { return .literal(.string(readQuoted(byte))) }
            if byte == UInt8(ascii: "/") { return readRegex() }
            if byte == UInt8(ascii: "[") { return readList() }
            let word = readWord()
            switch word {
            case "true": return .literal(.bool(true))
            case "false": return .literal(.bool(false))
            case "null": return .literal(.null)
            default:
                if let number = Double(word) { return .literal(.number(number, word)) }
                if word.isEmpty { failed = true }
                return .literal(.string(word))
            }
        }

        mutating func consume(_ token: String) -> Bool {
            skipSpaces()
            let tokenBytes = Array(token.trimmingCharacters(in: .whitespaces).utf8)
            let needsBoundary = token.hasPrefix(" ")
            guard index + tokenBytes.count <= bytes.count,
                  Array(bytes[index..<(index + tokenBytes.count)]) == tokenBytes else { return false }
            if needsBoundary, index + tokenBytes.count < bytes.count,
               bytes[index + tokenBytes.count] != 0x20 && bytes[index + tokenBytes.count] != UInt8(ascii: "[") {
                return false
            }
            index += tokenBytes.count
            return true
        }

        /// Đường dẫn tới khi gặp khoảng trắng/toán tử ở mức ngoài cùng (giữ ngoặc vuông và nháy bên trong).
        mutating func readPath() -> String {
            let start = index
            var depth = 0
            var quote: UInt8 = 0
            while index < bytes.count {
                let byte = bytes[index]
                if quote != 0 {
                    if byte == quote { quote = 0 }
                } else if byte == UInt8(ascii: "'") || byte == UInt8(ascii: "\"") {
                    quote = byte
                } else if byte == UInt8(ascii: "[") {
                    depth += 1
                } else if byte == UInt8(ascii: "]") {
                    depth -= 1
                } else if depth == 0, Self.isPathTerminator(byte) {
                    break
                }
                index += 1
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        static func isPathTerminator(_ byte: UInt8) -> Bool {
            [0x20, 0x09, UInt8(ascii: "="), UInt8(ascii: "!"), UInt8(ascii: "<"), UInt8(ascii: ">"),
             UInt8(ascii: "&"), UInt8(ascii: "|"), UInt8(ascii: ")")].contains(byte)
        }

        mutating func readQuoted(_ quote: UInt8) -> String {
            index += 1
            var buffer: [UInt8] = []
            while index < bytes.count, bytes[index] != quote {
                if bytes[index] == UInt8(ascii: "\\"), index + 1 < bytes.count { index += 1 }
                buffer.append(bytes[index])
                index += 1
            }
            index = min(index + 1, bytes.count)
            return String(decoding: buffer, as: UTF8.self)
        }

        mutating func readRegex() -> Node {
            index += 1
            var buffer: [UInt8] = []
            while index < bytes.count, bytes[index] != UInt8(ascii: "/") {
                if bytes[index] == UInt8(ascii: "\\"), index + 1 < bytes.count {
                    buffer.append(bytes[index])
                    index += 1
                }
                buffer.append(bytes[index])
                index += 1
            }
            index = min(index + 1, bytes.count)
            var options: NSRegularExpression.Options = []
            while index < bytes.count, bytes[index] >= 97, bytes[index] <= 122 {
                if bytes[index] == UInt8(ascii: "i") { options.insert(.caseInsensitive) }
                index += 1
            }
            let pattern = String(decoding: buffer, as: UTF8.self)
            return .regex(try? NSRegularExpression(pattern: pattern, options: options))
        }

        mutating func readList() -> Node {
            let start = index
            var depth = 0
            while index < bytes.count {
                if bytes[index] == UInt8(ascii: "[") { depth += 1 }
                if bytes[index] == UInt8(ascii: "]") {
                    depth -= 1
                    if depth == 0 { index += 1; break }
                }
                index += 1
            }
            let text = String(decoding: bytes[start..<index], as: UTF8.self)
            let parsed = LegadoEngineJSONParser.parse(text, lenient: true)
            return .list(parsed?.arrayValue ?? [])
        }

        mutating func readWord() -> String {
            let start = index
            while index < bytes.count, !Self.isPathTerminator(bytes[index]), bytes[index] != UInt8(ascii: "(") {
                index += 1
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }
    }
}
