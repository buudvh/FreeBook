import Foundation

/// Phân tích biểu thức XPath thành danh sách `LegadoXPathStep`.
///
/// Chỉ nhận tập con đủ dùng cho nguồn truyện: trục con/hậu duệ, `*`, `text()`, `@attr`, và vị ngữ
/// `[n]`, `[last()]`, `[@a]`, `[@a='v']`, `[contains(…)]`, `[starts-with(…)]`. Mọi vị ngữ khác thành
/// `.unsupported` để engine báo `LegadoUnsupportedFeature.xpathBeyondSubset` thay vì trả sai.
public enum LegadoXPathParser {

    private static let cache = LegadoRuleCache<[LegadoXPathStep]>(limit: 256)

    public static func parse(_ expression: String) -> [LegadoXPathStep] {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let cached = cache.value(for: trimmed) { return cached }
        let steps = build(trimmed)
        cache.set(steps, for: trimmed)
        return steps
    }

    private static func build(_ expression: String) -> [LegadoXPathStep] {
        var steps: [LegadoXPathStep] = []
        let chars = Array(expression)
        var index = 0

        while index < chars.count {
            var axis: LegadoXPathStep.Axis = .child
            if chars[index] == "/" {
                index += 1
                if index < chars.count, chars[index] == "/" {
                    axis = .descendant
                    index += 1
                }
            } else if steps.isEmpty {
                // Biểu thức tương đối (`div/a`) — bước đầu tính là con trực tiếp.
                axis = .child
            }

            var body = ""
            var scanner = BalanceScanner()
            while index < chars.count {
                let char = chars[index]
                let scalar = char.unicodeScalars.first ?? " "
                if scalar == "/" && scanner.isAtTopLevel { break }
                scanner.consume(scalar)
                body.append(char)
                index += 1
            }

            let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBody.isEmpty else { continue }
            steps.append(parseStep(trimmedBody, axis: axis))
        }
        return steps
    }

    private static func parseStep(_ body: String, axis: LegadoXPathStep.Axis) -> LegadoXPathStep {
        var nodePart = body
        var predicates: [LegadoXPathStep.Predicate] = []

        while let open = nodePart.firstIndex(of: "["), let close = matchingBracket(in: nodePart, from: open) {
            let inner = String(nodePart[nodePart.index(after: open)..<close])
            predicates.append(parsePredicate(inner))
            nodePart.removeSubrange(open...close)
        }

        let name = nodePart.trimmingCharacters(in: .whitespacesAndNewlines)
        let nodeTest: LegadoXPathStep.NodeTest
        if name.hasPrefix("@") {
            nodeTest = .attribute(String(name.dropFirst()))
        } else if name == "text()" {
            nodeTest = .text
        } else if name == "*" || name.isEmpty {
            nodeTest = .anyElement
        } else if name == "node()" {
            nodeTest = .anyElement
        } else {
            // Bỏ tiền tố trục viết dài (`child::div`), không hỗ trợ trục khác.
            let stripped = name.contains("::")
                ? String(name.split(separator: ":").last ?? "")
                : name
            nodeTest = .element(stripped)
        }

        return LegadoXPathStep(axis: axis, nodeTest: nodeTest, predicates: predicates)
    }

    private static func parsePredicate(_ raw: String) -> LegadoXPathStep.Predicate {
        let inner = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inner.isEmpty else { return .unsupported(raw) }

        if let position = Int(inner) { return .position(position) }
        if inner == "last()" { return .last }

        if inner.lowercased().hasPrefix("contains(") {
            guard let arguments = functionArguments(inner) else { return .unsupported(raw) }
            guard let target = parseTarget(arguments.0) else { return .unsupported(raw) }
            return .contains(target: target, value: unquote(arguments.1))
        }

        if inner.lowercased().hasPrefix("starts-with(") {
            guard let arguments = functionArguments(inner) else { return .unsupported(raw) }
            guard let target = parseTarget(arguments.0) else { return .unsupported(raw) }
            return .startsWith(target: target, value: unquote(arguments.1))
        }

        for symbol in ["!=", "="] {
            guard let range = inner.range(of: symbol) else { continue }
            let left = String(inner[inner.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let right = unquote(String(inner[range.upperBound...]))
            guard left.hasPrefix("@") else { return .unsupported(raw) }
            return .attributeEquals(
                name: String(left.dropFirst()),
                value: right,
                negated: symbol == "!="
            )
        }

        if inner.hasPrefix("@") {
            return .hasAttribute(String(inner.dropFirst()))
        }

        return .unsupported(raw)
    }

    private static func parseTarget(_ raw: String) -> LegadoXPathStep.Target? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") { return .attribute(String(trimmed.dropFirst())) }
        if trimmed == "text()" || trimmed == "." { return .text }
        return nil
    }

    /// Cắt hai tham số của `f(a, b)`, tôn trọng nháy.
    private static func functionArguments(_ raw: String) -> (String, String)? {
        guard let open = raw.firstIndex(of: "("), let close = raw.lastIndex(of: ")") else { return nil }
        let body = String(raw[raw.index(after: open)..<close])
        let parts = LegadoRuleLexer.split(body, separator: ",")
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1...].joined(separator: ","))
    }

    private static func matchingBracket(in text: String, from open: String.Index) -> String.Index? {
        var depth = 0
        var index = open
        while index < text.endIndex {
            let char = text[index]
            if char == "[" { depth += 1 }
            if char == "]" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func unquote(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
    }
}
