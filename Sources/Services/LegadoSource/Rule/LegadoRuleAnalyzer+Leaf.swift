import Foundation

/// Đánh giá một **lá** của biểu thức rule (spec §2.3): bóc `@put`, tách đuôi `##`, chọn mẫu hay chế độ, áp regex.
extension LegadoRuleAnalyzer {
    func evaluateLeaf(_ text: String, kind: Kind, content: LegadoContentNode) throws -> LeafResult {
        try session.checkCancellation()
        let extracted = LegadoRuleScanner.extractPuts(text)
        for put in extracted.puts {
            try runPut(put, content: content)
        }
        let parts = LegadoRuleScanner.splitRegexTail(extracted.rest)
        let selector = parts.selector.trimmingCharacters(in: .whitespacesAndNewlines)
        if selector.isEmpty && parts.tail == nil {
            return LeafResult(value: emptyValue(kind), hadEmptyPlaceholder: false)
        }

        switch kind {
        case .elements:
            if parts.tail != nil {
                session.diagnostics.record(.ruleSyntax, "Bỏ qua đuôi ## trên rule danh sách: \(text.prefix(80))")
            }
            if selector.isEmpty { return LeafResult(value: .list([]), hadEmptyPlaceholder: false) }
            let selection = try selectItems(selector, content: content)
            return LeafResult(value: .list(selection.items), hadEmptyPlaceholder: selection.hadEmptyPlaceholder)

        case .stringList:
            let selection = try selectStrings(selector, kind: kind, content: content)
            var values = selection.values
            if let tail = parts.tail {
                var transformed: [String] = []
                for value in values {
                    let changed = try applyTail(tail, to: value, content: content)
                    transformed.append(changed)
                }
                values = transformed
            }
            let items = values.filter { !$0.isEmpty }.map { LegadoContentNode.string($0) }
            return LeafResult(value: .list(items), hadEmptyPlaceholder: selection.hadEmptyPlaceholder)

        case .string:
            let selection = try selectStrings(selector, kind: kind, content: content)
            var joined = selection.values.joined(separator: "\n")
            if let tail = parts.tail {
                joined = try applyTail(tail, to: joined, content: content)
            }
            return LeafResult(value: .string(joined), hadEmptyPlaceholder: selection.hadEmptyPlaceholder)
        }
    }

    // MARK: - Đuôi regex (§2.6)

    /// `##R` xoá mọi đoạn khớp, `##R##P` thay mọi đoạn, `##R##P###` trích khớp đầu (không khớp ⇒ giữ nguyên, U3).
    /// Placeholder trong regex được thay giá trị **thô**; regex sau khi thay không biên dịch được thì thay lại bằng giá
    /// trị đã escape. Regex hỏng hẳn ⇒ bỏ bước regex, giữ chuỗi.
    func applyTail(_ tail: LegadoRuleScanner.RegexTail, to text: String, content: LegadoContentNode) throws -> String {
        var pattern = tail.pattern
        if LegadoRuleScanner.containsPlaceholder(pattern) {
            let raw = try renderTemplate(pattern, content: content, mode: .raw, substitutesGroups: false).text
            if LegadoRegexCache.shared.regex(raw) != nil {
                pattern = raw
            } else {
                pattern = try renderTemplate(pattern, content: content, mode: .regexEscaped, substitutesGroups: false).text
            }
        }
        var replacement = tail.replacement ?? ""
        if LegadoRuleScanner.containsPlaceholder(replacement) {
            replacement = try renderTemplate(replacement, content: content, mode: .templateEscaped, substitutesGroups: false).text
        }
        if tail.ignoredParts > 0 {
            session.diagnostics.record(.ruleSyntax, "Đuôi regex có hơn một cặp ##, phần dư bị bỏ: \(tail.pattern.prefix(60))")
        }
        guard !pattern.isEmpty else { return text }
        guard let regex = LegadoRegexCache.shared.regex(pattern) else {
            session.diagnostics.record(.ruleSyntax, "Regex không biên dịch được: \(pattern.prefix(80))")
            return text
        }
        if tail.firstMatchOnly {
            return LegadoRegexCache.firstMatch(regex, in: text, template: replacement)
        }
        return LegadoRegexCache.replaceAll(regex, in: text, template: replacement)
    }

    /// Chuỗi nguồn của nội dung; với tài liệu gốc của analyzer dùng thân thô `src` (không dựng lại từ cây).
    func sourceText(of node: LegadoContentNode) -> String {
        if isRootDocument(node), let src { return src }
        return node.sourceText
    }

    func isRootDocument(_ node: LegadoContentNode) -> Bool {
        guard case .html(let element) = node, case .html(let root) = content else { return false }
        return element === root
    }
}
