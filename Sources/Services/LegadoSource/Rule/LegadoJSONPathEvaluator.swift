import Foundation

/// JSONPath tự viết cho rule nguồn Legado (spec §2.11): `$`, `.khoá`, `['khoá']`, `[n]`, `[-n]`, `[*]`, `.*`,
/// quét sâu `..`, hợp `[0,1]`/`['a','b']`, slice `[a:b:c]`, filter `[?(…)]`, và `[(@.length-n)]`.
///
/// `isDefinite` = đường dẫn không có wildcard/quét sâu/filter/hợp/slice; dùng để quyết định một mảng duy nhất là
/// "danh sách mục" hay "một giá trị" (§2.11.3).
struct LegadoJSONPathEvaluator {
    struct Result {
        var values: [LegadoEngineJSON]
        var isDefinite: Bool
    }

    indirect enum Step {
        case child(String)
        case children([String])
        case indices([Int])
        case slice(Int?, Int?, Int?)
        case wildcard
        case filter(LegadoJSONPathFilter)
        case lengthOffset(Int)
        case recursive(Step)
    }

    private let bytes: [UInt8]
    private var index = 0
    private(set) var steps: [Step] = []
    private(set) var isDefinite = true
    private(set) var isValid = true

    /// Thêm tiền tố ngầm (§2.11.1): không bắt đầu bằng `$`/`@` ⇒ bắt đầu bằng `.`/`[` thì thêm `$`, còn lại thêm `$.`.
    static func normalized(_ rule: String) -> String {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("$") || trimmed.hasPrefix("@") { return trimmed }
        if trimmed.hasPrefix(".") || trimmed.hasPrefix("[") { return "$" + trimmed }
        return "$." + trimmed
    }

    static func evaluate(_ path: String, on root: LegadoEngineJSON) -> Result {
        evaluate(path, on: root, root: root)
    }

    /// `current` là nút `@` (trong filter), `root` là nút `$`.
    static func evaluate(_ path: String, on current: LegadoEngineJSON, root: LegadoEngineJSON) -> Result {
        var parser = LegadoJSONPathEvaluator(text: normalized(path))
        parser.parse()
        guard parser.isValid else { return Result(values: [], isDefinite: true) }
        let start = parser.startsAtRoot ? root : current
        var values = [start]
        for step in parser.steps {
            values = apply(step, to: values, root: root)
            if values.isEmpty { break }
        }
        return Result(values: values, isDefinite: parser.isDefinite)
    }

    private var startsAtRoot = true

    private init(text: String) {
        bytes = Array(text.utf8)
    }

    // MARK: - Parse

    private mutating func parse() {
        guard index < bytes.count else { isValid = false; return }
        startsAtRoot = bytes[index] != UInt8(ascii: "@")
        index += 1
        while index < bytes.count && isValid {
            let byte = bytes[index]
            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\t") {
                index += 1
            } else if byte == UInt8(ascii: ".") {
                if index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: ".") {
                    index += 2
                    isDefinite = false
                    guard let inner = parseAfterDot() else { isValid = false; return }
                    steps.append(.recursive(inner))
                } else {
                    index += 1
                    guard let step = parseAfterDot() else { isValid = false; return }
                    steps.append(step)
                }
            } else if byte == UInt8(ascii: "[") {
                guard let step = parseBracket() else { isValid = false; return }
                steps.append(step)
            } else {
                let name = readName()
                steps.append(.child(name))
            }
        }
    }

    private mutating func parseAfterDot() -> Step? {
        guard index < bytes.count else { return nil }
        if bytes[index] == UInt8(ascii: "*") {
            index += 1
            isDefinite = false
            return .wildcard
        }
        if bytes[index] == UInt8(ascii: "[") { return parseBracket() }
        let name = readName()
        return name.isEmpty ? nil : .child(name)
    }

    private mutating func readName() -> String {
        let start = index
        while index < bytes.count, bytes[index] != UInt8(ascii: "."), bytes[index] != UInt8(ascii: "[") {
            index += 1
        }
        return String(decoding: bytes[start..<index], as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }

    private mutating func parseBracket() -> Step? {
        index += 1
        guard let close = matchingBracketEnd() else { return nil }
        let inner = String(decoding: bytes[index..<close], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        index = close + 1
        if inner == "*" {
            isDefinite = false
            return .wildcard
        }
        if inner.hasPrefix("?") {
            isDefinite = false
            var body = String(inner.dropFirst()).trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("("), body.hasSuffix(")") { body = String(body.dropFirst().dropLast()) }
            return .filter(LegadoJSONPathFilter(body))
        }
        if inner.hasPrefix("("), inner.hasSuffix(")") {
            return Self.lengthExpression(String(inner.dropFirst().dropLast()))
        }
        if inner.hasPrefix("'") || inner.hasPrefix("\"") {
            let names = Self.quotedNames(inner)
            if names.count != 1 { isDefinite = false }
            return names.count == 1 ? .child(names[0]) : .children(names)
        }
        if inner.contains(":") {
            isDefinite = false
            let parts = inner.split(separator: ":", omittingEmptySubsequences: false).map {
                Int($0.trimmingCharacters(in: .whitespaces))
            }
            return .slice(parts.first ?? nil, parts.count > 1 ? parts[1] : nil, parts.count > 2 ? parts[2] : nil)
        }
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let numbers = parts.compactMap { Int($0) }
        if numbers.count == parts.count, !numbers.isEmpty {
            if numbers.count != 1 { isDefinite = false }
            return .indices(numbers)
        }
        if parts.count != 1 { isDefinite = false }
        return parts.count == 1 ? .child(parts[0]) : .children(parts)
    }

    /// Vị trí `]` đóng ngoặc đang mở (bỏ qua ngoặc lồng và chuỗi nháy).
    private func matchingBracketEnd() -> Int? {
        var depth = 0
        var quote: UInt8 = 0
        var cursor = index
        while cursor < bytes.count {
            let byte = bytes[cursor]
            if quote != 0 {
                if byte == UInt8(ascii: "\\") { cursor += 1 } else if byte == quote { quote = 0 }
            } else if byte == UInt8(ascii: "'") || byte == UInt8(ascii: "\"") {
                quote = byte
            } else if byte == UInt8(ascii: "[") || byte == UInt8(ascii: "(") {
                depth += 1
            } else if byte == UInt8(ascii: ")") {
                depth -= 1
            } else if byte == UInt8(ascii: "]") {
                if depth == 0 { return cursor }
                depth -= 1
            }
            cursor += 1
        }
        return nil
    }

    private static func quotedNames(_ text: String) -> [String] {
        var names: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in text {
            if let activeQuote = quote {
                if escaped {
                    current.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == activeQuote {
                    names.append(current)
                    current = ""
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "'" || character == "\"" {
                quote = character
            }
        }
        return names
    }

    /// `@.length-1` / `@.length - 2`: chỉ số tính từ cuối. Biểu thức khác không hỗ trợ.
    private static func lengthExpression(_ text: String) -> Step? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard compact.hasPrefix("@.length") else { return nil }
        let rest = compact.dropFirst("@.length".count)
        if rest.isEmpty { return .lengthOffset(0) }
        guard let offset = Int(rest) else { return nil }
        return .lengthOffset(offset)
    }

    // MARK: - Áp bước

    private static func apply(_ step: Step, to values: [LegadoEngineJSON], root: LegadoEngineJSON) -> [LegadoEngineJSON] {
        var output: [LegadoEngineJSON] = []
        for value in values {
            switch step {
            case .recursive(let inner):
                var nodes: [LegadoEngineJSON] = []
                collectDescendants(of: value, into: &nodes)
                output.append(contentsOf: apply(inner, to: nodes, root: root))
            default:
                output.append(contentsOf: applySingle(step, to: value, root: root))
            }
        }
        return output
    }

    private static func applySingle(_ step: Step, to value: LegadoEngineJSON, root: LegadoEngineJSON) -> [LegadoEngineJSON] {
        switch step {
        case .child(let name):
            if let found = value[name] { return [found] }
            if case .array(let items) = value, let position = Int(name), let item = element(items, position) {
                return [item]
            }
            return []
        case .children(let names):
            return names.compactMap { value[$0] }
        case .indices(let positions):
            guard case .array(let items) = value else { return [] }
            return positions.compactMap { element(items, $0) }
        case .lengthOffset(let offset):
            guard case .array(let items) = value else { return [] }
            return element(items, items.count + offset).map { [$0] } ?? []
        case .slice(let start, let end, let step):
            guard case .array(let items) = value else { return [] }
            return slice(items, start: start, end: end, step: step)
        case .wildcard:
            return children(of: value)
        case .filter(let filter):
            return children(of: value).filter { filter.matches($0, root: root) }
        case .recursive(let inner):
            var nodes: [LegadoEngineJSON] = []
            collectDescendants(of: value, into: &nodes)
            return apply(inner, to: nodes, root: root)
        }
    }

    private static func element(_ items: [LegadoEngineJSON], _ position: Int) -> LegadoEngineJSON? {
        let resolved = position < 0 ? items.count + position : position
        guard resolved >= 0, resolved < items.count else { return nil }
        return items[resolved]
    }

    private static func slice(_ items: [LegadoEngineJSON], start: Int?, end: Int?, step: Int?) -> [LegadoEngineJSON] {
        let count = items.count
        let stride = step ?? 1
        guard stride != 0, count > 0 else { return [] }
        func clamp(_ value: Int, defaultValue: Int) -> Int {
            let resolved = value < 0 ? count + value : value
            return min(max(resolved, stride > 0 ? 0 : -1), stride > 0 ? count : count - 1)
        }
        var cursor = start.map { clamp($0, defaultValue: 0) } ?? (stride > 0 ? 0 : count - 1)
        let limit = end.map { clamp($0, defaultValue: count) } ?? (stride > 0 ? count : -1)
        var output: [LegadoEngineJSON] = []
        while stride > 0 ? cursor < limit : cursor > limit {
            if cursor >= 0 && cursor < count { output.append(items[cursor]) }
            cursor += stride
        }
        return output
    }

    private static func children(of value: LegadoEngineJSON) -> [LegadoEngineJSON] {
        switch value {
        case .array(let items): return items
        case .object(let entries): return entries.map { $0.value }
        default: return []
        }
    }

    /// Thứ tự trước (pre-order): chính nút rồi tới con cháu.
    private static func collectDescendants(of value: LegadoEngineJSON, into nodes: inout [LegadoEngineJSON]) {
        nodes.append(value)
        for child in children(of: value) where child.isContainer {
            collectDescendants(of: child, into: &nodes)
        }
    }
}
