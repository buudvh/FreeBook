import Foundation

/// Chế độ mẫu (spec §2.7): phần chữ giữ nguyên, placeholder `{{X}}`, `{$.x}`, `@get:{k}` (và `$n` trên mục regex
/// danh sách, §2.13) được thay bằng giá trị.
extension LegadoRuleAnalyzer {
    enum TemplateValueMode {
        /// Giá trị thô (phần-chọn, mã JS, regex lần thử đầu).
        case raw
        /// Escape cho pattern regex (regex sau khi thay thô không biên dịch được).
        case regexEscaped
        /// Escape cho chuỗi thay thế của regex (`$`, `\`).
        case templateEscaped
    }

    struct TemplateRender {
        var text: String
        /// Có ít nhất một placeholder cho chuỗi rỗng (vế `||` coi là thất bại, U6).
        var hadEmptyPlaceholder: Bool
    }

    func renderTemplate(_ text: String, content: LegadoContentNode, mode: TemplateValueMode,
                        substitutesGroups: Bool = false, isScript: Bool = false) throws -> TemplateRender {
        var output = ""
        var hadEmpty = false
        for part in LegadoRuleScanner.templateParts(text, allowsSingleBrace: !isScript) {
            let value: String
            switch part {
            case .text(let literal):
                output += substitutesGroups ? substituteRegexGroups(literal, content: content) : literal
                continue
            case .expression(let inner):
                value = try placeholderValue(inner, content: content)
            case .jsonPath(let path):
                value = jsonPathString(path, content: content)
            case .variable(let key):
                value = session.ruleVariable(key)
            }
            if value.isEmpty { hadEmpty = true }
            switch mode {
            case .raw: output += value
            case .regexEscaped: output += NSRegularExpression.escapedPattern(for: value)
            case .templateEscaped: output += NSRegularExpression.escapedTemplate(for: value)
            }
        }
        return TemplateRender(text: output, hadEmptyPlaceholder: hadEmpty)
    }

    /// `{{X}}`: có dấu hiệu chế độ, hoặc mở đầu bằng `@` ⇒ rule `getString` trên nội dung hiện hành; không có ⇒ JS
    /// (`undefined`/`null` ⇒ rỗng). Không câu JS nào mở đầu bằng `@`: 梧桐中文 `{{@.w_txt li.4@textNodes}}`, 飞卢, 酷书阁,
    /// SF轻小说 (corpus: 50 chỗ ở 27 nguồn, không chỗ nào là JS).
    ///
    /// JS trên **trang gốc** nhận `result` = thân thô của trang (chuỗi) như phân đoạn JS đứng đầu (§2.2), không phải phần
    /// tử HTML: 豆瓣读书 `{{html='';if(result.match(/ratingValue": "(\d+)"/))…}}`. `src` theo phân đoạn JS (§6.2).
    func placeholderValue(_ inner: String, content: LegadoContentNode) throws -> String {
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if Self.hasModeMarker(trimmed) || trimmed.hasPrefix("@") {
            return try evaluate(trimmed, kind: .string, content: content).finalString
        }
        let input: LegadoContentNode
        if isRootDocument(content), let src {
            input = .string(src)
        } else {
            input = content
        }
        return try session.evaluateScript(trimmed, result: input, baseUrl: baseUrl, src: itemScriptSource()).finalString
    }

    static func hasModeMarker(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("@@") || lower.hasPrefix("@css:") || lower.hasPrefix("@xpath:")
            || lower.hasPrefix("@json:") || lower.hasPrefix("//") || lower.hasPrefix("$.") || lower.hasPrefix("$[")
    }

    /// `{$.x}`: JSONPath `getString` trên nội dung hiện hành.
    func jsonPathString(_ path: String, content: LegadoContentNode) -> String {
        guard let json = content.jsonValue else { return "" }
        return LegadoJSONPathEvaluator.evaluate(path, on: json).values
            .map { $0.scalarString }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static let groupReference = try? NSRegularExpression(pattern: "\\$(\\d{1,2})")

    /// `$0`, `$1`… → nhóm của mục regex danh sách; nhóm không có ⇒ rỗng. Nội dung không phải mục regex thì giữ nguyên.
    func substituteRegexGroups(_ text: String, content: LegadoContentNode) -> String {
        guard case .regexMatch(let groups) = content, text.contains("$"), let regex = Self.groupReference else {
            return text
        }
        let nsText = text as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            output += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let number = Int(nsText.substring(with: match.range(at: 1))) ?? -1
            output += number >= 0 && number < groups.count ? groups[number] : ""
            cursor = match.range.location + match.range.length
        }
        output += nsText.substring(from: cursor)
        return output
    }
}
