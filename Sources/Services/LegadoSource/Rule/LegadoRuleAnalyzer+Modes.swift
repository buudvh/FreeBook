import Foundation
import SwiftSoup

/// Nhận diện chế độ của một lá (spec §2.4) và đánh giá theo từng chế độ: mặc định/CSS (§2.8, §2.9), JSONPath (§2.11),
/// XPath (§2.12), regex danh sách `:` (§2.13).
extension LegadoRuleAnalyzer {
    enum Mode {
        case jsoup(String)
        case css(String)
        case jsonPath(String)
        case xpath(String)
    }

    struct ItemSelection {
        var items: [LegadoContentNode]
        var hadEmptyPlaceholder: Bool
    }

    struct StringSelection {
        var values: [String]
        var hadEmptyPlaceholder: Bool
    }

    // MARK: - Nhận diện (§2.4)

    func detectMode(_ selector: String, content: LegadoContentNode) -> Mode {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("@@") {
            let rest = String(trimmed.dropFirst(2))
            let restLower = rest.lowercased()
            if restLower.hasPrefix("@css:") || restLower.hasPrefix("@xpath:") || restLower.hasPrefix("@json:") {
                return detectMode(rest, content: content)
            }
            return .jsoup(rest)
        }
        if lower.hasPrefix("@xpath:") { return .xpath(String(trimmed.dropFirst(7))) }
        if lower.hasPrefix("@css:") { return .css(String(trimmed.dropFirst(5))) }
        if lower.hasPrefix("@json:") { return .jsonPath(String(trimmed.dropFirst(6))) }
        if trimmed.hasPrefix("//") { return .xpath(trimmed) }
        if trimmed.hasPrefix("$.") || trimmed.hasPrefix("$[") { return .jsonPath(trimmed) }
        if contentIsJSON(content) { return .jsonPath(trimmed) }
        if content.isXPathNode, trimmed.hasPrefix("/") { return .xpath(trimmed) }
        return .jsoup(trimmed)
    }

    private func contentIsJSON(_ node: LegadoContentNode) -> Bool {
        switch node {
        case .json: return true
        case .string: return node.isJSONLike
        case .list(let items):
            guard let first = items.first else { return false }
            if case .json = first { return true }
            return false
        default: return false
        }
    }

    /// Có dùng chế độ mẫu không (§2.7): placeholder trong phần-chọn, hoặc `$n` trên mục regex danh sách (§2.13).
    func usesTemplate(_ selector: String, content: LegadoContentNode) -> Bool {
        if LegadoRuleScanner.containsPlaceholder(selector) { return true }
        if case .regexMatch = content, selector.range(of: "\\$\\d", options: .regularExpression) != nil { return true }
        return false
    }

    // MARK: - Chọn

    func selectStrings(_ selector: String, kind: Kind, content: LegadoContentNode) throws -> StringSelection {
        if selector.isEmpty {
            return StringSelection(values: [sourceText(of: content)], hadEmptyPlaceholder: false)
        }
        if usesTemplate(selector, content: content) {
            let rendered = try renderTemplate(selector, content: content, mode: .raw, substitutesGroups: true)
            return StringSelection(values: [rendered.text], hadEmptyPlaceholder: rendered.hadEmptyPlaceholder)
        }
        switch detectMode(selector, content: content) {
        case .jsoup(let rule):
            return StringSelection(values: htmlStrings(rule, cssOnly: false, content: content), hadEmptyPlaceholder: false)
        case .css(let rule):
            return StringSelection(values: htmlStrings(rule, cssOnly: true, content: content), hadEmptyPlaceholder: false)
        case .jsonPath(let path):
            return StringSelection(values: jsonStrings(path, kind: kind, content: content), hadEmptyPlaceholder: false)
        case .xpath(let expression):
            let values = xpathItems(expression, content: content).map { item -> String in
                switch item.1 {
                case .node(let pointer): return LegadoXPathDocument.content(of: pointer)
                case .text(let text): return text
                }
            }.filter { !$0.isEmpty }
            return StringSelection(values: values, hadEmptyPlaceholder: false)
        }
    }

    func selectItems(_ selector: String, content: LegadoContentNode) throws -> ItemSelection {
        if usesTemplate(selector, content: content) {
            let rendered = try renderTemplate(selector, content: content, mode: .raw, substitutesGroups: true)
            return ItemSelection(items: LegadoContentNode.string(rendered.text).finalElements,
                                 hadEmptyPlaceholder: rendered.hadEmptyPlaceholder)
        }
        switch detectMode(selector, content: content) {
        case .jsoup(let rule):
            return ItemSelection(items: htmlItems(rule, cssOnly: false, content: content), hadEmptyPlaceholder: false)
        case .css(let rule):
            return ItemSelection(items: htmlItems(rule, cssOnly: true, content: content), hadEmptyPlaceholder: false)
        case .jsonPath(let path):
            return ItemSelection(items: jsonItems(path, content: content), hadEmptyPlaceholder: false)
        case .xpath(let expression):
            let items = xpathItems(expression, content: content).map { item -> LegadoContentNode in
                switch item.1 {
                case .node(let pointer): return .xpath(LegadoXPathNode(document: item.0, pointer: pointer))
                case .text(let text): return .string(text)
                }
            }
            return ItemSelection(items: items, hadEmptyPlaceholder: false)
        }
    }

    // MARK: - HTML

    private func makeSelector(cssOnly: Bool) -> LegadoJsoupSelector {
        LegadoJsoupSelector(cssOnly: cssOnly, report: { [weak self] message in self?.reportSelectorError(message) })
    }

    private func htmlStrings(_ rule: String, cssOnly: Bool, content: LegadoContentNode) -> [String] {
        if case .list(let items) = content {
            return items.flatMap { htmlStrings(rule, cssOnly: cssOnly, content: $0) }
        }
        guard let element = content.htmlElement(baseUrl: baseUrl) else { return [] }
        return makeSelector(cssOnly: cssOnly).strings(rule, in: element)
    }

    private func htmlItems(_ rule: String, cssOnly: Bool, content: LegadoContentNode) -> [LegadoContentNode] {
        if case .list(let items) = content {
            return items.flatMap { htmlItems(rule, cssOnly: cssOnly, content: $0) }
        }
        guard let element = content.htmlElement(baseUrl: baseUrl) else { return [] }
        return makeSelector(cssOnly: cssOnly).elements(rule, in: element).map { LegadoContentNode.html($0) }
    }

    // MARK: - JSON (§2.11.3)

    private func jsonStrings(_ path: String, kind: Kind, content: LegadoContentNode) -> [String] {
        guard let json = content.jsonValue else { return [] }
        let result = LegadoJSONPathEvaluator.evaluate(path, on: json)
        if kind == .stringList, result.isDefinite, result.values.count == 1, case .array(let items) = result.values[0] {
            return items.map { $0.scalarString }.filter { !$0.isEmpty }
        }
        return result.values.map { $0.scalarString }.filter { !$0.isEmpty }
    }

    private func jsonItems(_ path: String, content: LegadoContentNode) -> [LegadoContentNode] {
        guard let json = content.jsonValue else { return [] }
        let result = LegadoJSONPathEvaluator.evaluate(path, on: json)
        if result.isDefinite, result.values.count == 1 {
            switch result.values[0] {
            case .array(let items): return items.map { LegadoContentNode.json($0) }
            case .null: return []
            default: return [.json(result.values[0])]
            }
        }
        return result.values.filter { !$0.isNull }.map { LegadoContentNode.json($0) }
    }

    // MARK: - XPath (§2.12)

    func xpathItems(_ expression: String, content: LegadoContentNode) -> [(LegadoXPathDocument, LegadoXPathDocument.Item)] {
        switch content {
        case .xpath(let node):
            return node.evaluate(expression).map { (node.document, $0) }
        case .html(let element):
            if isRootDocument(content) {
                guard let document = rootXPathDocument(element) else { return [] }
                return document.evaluate(expression, at: nil).map { (document, $0) }
            }
            let html = (try? element.outerHtml()) ?? ""
            guard let document = LegadoXPathDocument(html: html) else { return [] }
            if element is Document {
                return document.evaluate(expression, at: nil).map { (document, $0) }
            }
            let root = document.fragmentRoot(expectedTag: element.tagName())
            return document.evaluate(LegadoXPathNode.relative(expression), at: root).map { (document, $0) }
        case .list(let items):
            return items.flatMap { xpathItems(expression, content: $0) }
        case .null:
            return []
        default:
            guard let document = LegadoXPathDocument(html: content.sourceText) else { return [] }
            return document.evaluate(expression, at: nil).map { (document, $0) }
        }
    }

    private func rootXPathDocument(_ element: Element) -> LegadoXPathDocument? {
        if let cached = xpathRootDocument { return cached }
        let html = src ?? ((try? element.outerHtml()) ?? "")
        let made = LegadoXPathDocument(html: html)
        xpathRootDocument = made
        return made
    }

    // MARK: - Regex danh sách (§2.13)

    /// `:R` — mỗi đoạn khớp là một mục `.regexMatch`. `:R1&&R2` — `R1` lấy vùng (khớp đầu), `R2` lấy mục trong vùng (U15).
    func regexList(_ text: String, content: LegadoContentNode) -> [LegadoContentNode] {
        var region = sourceText(of: content)
        let patterns = text.components(separatedBy: "&&").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for (position, pattern) in patterns.enumerated() {
            guard let regex = LegadoRegexCache.shared.regex(pattern) else {
                session.diagnostics.record(.ruleSyntax, "Regex danh sách không biên dịch được: \(pattern.prefix(80))")
                return []
            }
            if position < patterns.count - 1 {
                let nsRegion = region as NSString
                guard let match = regex.firstMatch(in: region, range: NSRange(location: 0, length: nsRegion.length)) else {
                    return []
                }
                region = nsRegion.substring(with: match.range)
            } else {
                return LegadoRegexCache.allGroups(regex, in: region).map { LegadoContentNode.regexMatch($0) }
            }
        }
        return []
    }
}
