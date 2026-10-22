import Foundation

/// Rút token bộ chọn (class / id / tên thẻ) từ một rule danh sách hoặc nội dung — đầu vào của đầu dò bộ chọn
/// (`LegadoSelectorProbe`). Không phải parser rule đầy đủ: chỉ cần đủ để hỏi "trang có phần tử mà rule nhắm tới không".
///
/// Các bước (cú pháp rule: spec §2.2–§2.13):
/// 1. Bóc tiền tố `-`/`+` của rule danh sách (§2.13.1).
/// 2. Rule **bắt đầu** bằng JS (`@js:`/`<js>`) ⇒ nội dung bị JS thay trước khi chọn — trang gốc không phải bằng chứng ⇒
///    không token. JS nằm **sau** phần bộ chọn ⇒ chỉ lấy phần trước JS, đánh dấu `hasScript` (JS có thể lọc danh sách).
/// 3. Bỏ mẫu `{{…}}`, `@put:{…}`/`@get:{…}`; tách vế `||`/`&&`/`%%` ở mức ngoài cùng; mỗi vế bỏ đuôi regex `##…`.
/// 4. Vế JSONPath (`@json:`, `$.`, `$[`), regex danh sách (`:`) ⇒ không token. XPath (`//`, `@xpath:`) ⇒ chỉ lấy
///    `@class='…'`, `contains(@class,'…')`, `@id='…'`.
/// 5. Còn lại (mặc định / `@css:` / `@@`): tách bước theo `@`; trường chuỗi bỏ bước cuối (bước trích, §2.8.1). Mỗi bước:
///    bỏ chỉ số (`.0`, `.-1`, `!0:1`, `[1:]`), rồi `class.X` (X có dấu cách = đủ mọi class), `id.X`, `tag.X`;
///    `text.X`/`children` không token; còn lại là bộ chọn CSS ⇒ `.X`, `#X`, `[class=…]`, `[id=…]` (bỏ `[…]` khác và
///    giả lớp `:x(…)`).
enum LegadoRuleSelectorTokens {
    struct Parsed: Sendable, Equatable {
        /// Mỗi vế `||`/`&&`/`%%` có token (số đếm = 0, đầu dò điền sau).
        var leaves: [LegadoSelectorProbe.Leaf]
        /// Rule có JS sau phần bộ chọn (JS có thể lọc/biến đổi kết quả).
        var hasScript: Bool
    }

    /// `isList`: rule danh sách (`bookList`, `chapterList`) — mọi bước là bước chọn; ngược lại bước cuối là bước trích.
    static func parse(_ rule: String, isList: Bool) -> Parsed {
        var text = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if isList, let first = text.first, first == "-" || first == "+" {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let lower = text.lowercased()
        if lower.hasPrefix("@js:") || lower.hasPrefix("<js>") {
            return Parsed(leaves: [], hasScript: true)
        }
        var hasScript = false
        if let cut = firstScriptStart(in: text) {
            text = String(text[..<cut])
            hasScript = true
        }
        text = removing(#"\{\{[\s\S]*?\}\}"#, from: text)
        text = removing(#"@(?:put|get):\{[^}]*\}"#, from: text)
        var leaves: [LegadoSelectorProbe.Leaf] = []
        for part in splitOperators(text) {
            var body = part
            if let hash = body.range(of: "##") {
                body = String(body[..<hash.lowerBound])
            }
            if let leaf = makeLeaf(body.trimmingCharacters(in: .whitespacesAndNewlines), isList: isList) {
                leaves.append(leaf)
            }
        }
        return Parsed(leaves: leaves, hasScript: hasScript)
    }

    // MARK: - Vế

    private static func makeLeaf(_ leaf: String, isList: Bool) -> LegadoSelectorProbe.Leaf? {
        guard !leaf.isEmpty else { return nil }
        let lower = leaf.lowercased()
        if lower.hasPrefix("@json:") || lower.hasPrefix("$.") || lower.hasPrefix("$[") || lower.hasPrefix(":") {
            return nil
        }
        if lower.hasPrefix("@xpath:") || lower.hasPrefix("/") {
            let tokens = unique(xpathTokens(leaf))
            return tokens.isEmpty ? nil : LegadoSelectorProbe.Leaf(tokens: tokens, trailingTag: nil)
        }
        var selector = leaf
        if lower.hasPrefix("@css:") {
            selector = String(leaf.dropFirst(5))
        } else if lower.hasPrefix("@@") {
            selector = String(leaf.dropFirst(2))
        }
        var steps = splitSteps(selector)
        if !isList, !steps.isEmpty {
            steps.removeLast()
        }
        let tokens = unique(steps.flatMap(stepTokens))
        guard !tokens.isEmpty else { return nil }
        return LegadoSelectorProbe.Leaf(tokens: tokens, trailingTag: steps.last.flatMap(trailingTag))
    }

    /// Bước sau khi bỏ chỉ số cuối (`.0`, `.-1`, `!0:1`, `[1:]`).
    private static func strippedIndex(_ raw: String) -> String {
        var step = removing(#"(?:[.!]-?\d+(?::-?\d+)*|\[[-\d:,!\s]*\])$"#, from: raw.trimmingCharacters(in: .whitespaces))
        while step.hasSuffix(".") { step.removeLast() }
        return step
    }

    /// Thẻ của phần chọn cuối trong bước khi phần đó không có class/id: `tag.dd` ⇒ `dd`; CSS `.list li` ⇒ `li`.
    private static func trailingTag(_ raw: String) -> String? {
        let step = strippedIndex(raw)
        let lower = step.lowercased()
        if lower.hasPrefix("tag.") {
            let name = step.dropFirst(4).trimmingCharacters(in: .whitespaces).lowercased()
            return isTagName(name) ? name : nil
        }
        if lower.hasPrefix("class.") || lower.hasPrefix("id.") || lower.hasPrefix("text.") || lower == "children"
            || lower.contains("[class") || lower.contains("[id") {
            return nil
        }
        var css = removing(#"\[[^\]]*\]"#, from: step)
        css = removing(#":[A-Za-z-]+\((?:[^()]|\([^()]*\))*\)"#, from: css)
        css = removing(#":[A-Za-z-]+"#, from: css)
        let compounds = css.split(whereSeparator: { $0.isWhitespace || $0 == ">" || $0 == "+" || $0 == "~" || $0 == "," })
        guard let last = compounds.last.map({ String($0).lowercased() }), isTagName(last) else { return nil }
        return last
    }

    private static func isTagName(_ text: String) -> Bool {
        text.range(of: #"^[a-z][a-z0-9]*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func stepTokens(_ raw: String) -> [LegadoSelectorProbe.Token] {
        let step = strippedIndex(raw)
        let lower = step.lowercased()
        if lower.hasPrefix("class.") {
            let names = words(String(step.dropFirst(6)))
            return names.isEmpty ? [] : [LegadoSelectorProbe.Token(kind: .className, name: names.joined(separator: " "))]
        }
        if lower.hasPrefix("id.") {
            let name = step.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? [] : [LegadoSelectorProbe.Token(kind: .id, name: name)]
        }
        if lower.hasPrefix("tag.") {
            let name = step.dropFirst(4).trimmingCharacters(in: .whitespaces).lowercased()
            return name.isEmpty ? [] : [LegadoSelectorProbe.Token(kind: .tag, name: name)]
        }
        if lower.hasPrefix("text.") || lower == "children" {
            return []
        }
        return cssTokens(step)
    }

    /// Token của một bộ chọn CSS kiểu jsoup.
    private static func cssTokens(_ selector: String) -> [LegadoSelectorProbe.Token] {
        var tokens: [LegadoSelectorProbe.Token] = []
        for groups in matches(#"\[\s*(class|id)\s*=\s*["']?([^"'\]]+?)["']?\s*\]"#, in: selector) where groups.count == 2 {
            let names = words(groups[1])
            guard !names.isEmpty else { continue }
            if groups[0].lowercased() == "class" {
                tokens.append(LegadoSelectorProbe.Token(kind: .className, name: names.joined(separator: " ")))
            } else {
                tokens.append(LegadoSelectorProbe.Token(kind: .id, name: names.joined(separator: " ")))
            }
        }
        var css = removing(#"\[[^\]]*\]"#, from: selector)
        css = removing(#":[A-Za-z-]+\((?:[^()]|\([^()]*\))*\)"#, from: css)
        css = removing(#":[A-Za-z-]+"#, from: css)
        let name = #"(-?[\p{L}_][\p{L}\p{N}_-]*)"#
        for groups in matches(#"(?<!\\)\."# + name, in: css) {
            if let value = groups.first { tokens.append(LegadoSelectorProbe.Token(kind: .className, name: value)) }
        }
        for groups in matches(#"(?<!\\)#"# + name, in: css) {
            if let value = groups.first { tokens.append(LegadoSelectorProbe.Token(kind: .id, name: value)) }
        }
        return tokens
    }

    private static func xpathTokens(_ xpath: String) -> [LegadoSelectorProbe.Token] {
        var tokens: [LegadoSelectorProbe.Token] = []
        let patterns: [(String, LegadoSelectorProbe.TokenKind)] = [
            (#"@class\s*=\s*["']([^"']+)["']"#, .className),
            (#"contains\(\s*@class\s*,\s*["']([^"']+)["']\s*\)"#, .className),
            (#"@id\s*=\s*["']([^"']+)["']"#, .id)
        ]
        for (pattern, kind) in patterns {
            for groups in matches(pattern, in: xpath) {
                let names = words(groups.first ?? "")
                if !names.isEmpty { tokens.append(LegadoSelectorProbe.Token(kind: kind, name: names.joined(separator: " "))) }
            }
        }
        return tokens
    }

    // MARK: - Tách chuỗi

    /// Vị trí `<js>` hoặc `@js:` đầu tiên (không phân biệt hoa thường).
    private static func firstScriptStart(in text: String) -> String.Index? {
        let candidates = [
            text.range(of: "<js>", options: .caseInsensitive)?.lowerBound,
            text.range(of: "@js:", options: .caseInsensitive)?.lowerBound
        ].compactMap { $0 }
        return candidates.min()
    }

    /// Tách theo `||`, `&&`, `%%` ở mức ngoài cùng (bỏ qua trong `[…]`, `(…)`, nháy, sau `\`).
    private static func splitOperators(_ text: String) -> [String] {
        split(text) { previous, current in
            (previous == "|" && current == "|") || (previous == "&" && current == "&") || (previous == "%" && current == "%")
        }
    }

    /// Tách bước theo `@` ở mức ngoài cùng.
    private static func splitSteps(_ text: String) -> [String] {
        split(text) { _, current in current == "@" }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Bộ tách chung: `isSeparator(trước, hiện tại)` ⇒ cắt; separator hai ký tự thì bỏ cả ký tự trước.
    private static func split(_ text: String, isSeparator: (Character?, Character) -> Bool) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        var escaped = false
        var previous: Character?
        for character in text {
            defer { previous = character }
            if escaped {
                escaped = false
                current.append(character)
                continue
            }
            if character == "\\" {
                escaped = true
                current.append(character)
                continue
            }
            if let open = quote {
                if character == open { quote = nil }
                current.append(character)
                continue
            }
            switch character {
            case "\"", "'":
                quote = character
            case "[", "(":
                depth += 1
            case "]", ")":
                depth = max(0, depth - 1)
            default:
                break
            }
            if depth == 0, isSeparator(previous, character) {
                if character != "@", !current.isEmpty { current.removeLast() }
                parts.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        parts.append(current)
        return parts
    }

    // MARK: - Tiện ích

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func unique(_ tokens: [LegadoSelectorProbe.Token]) -> [LegadoSelectorProbe.Token] {
        var seen = Set<String>()
        return tokens.filter { seen.insert($0.kind.rawValue + "\u{1}" + $0.name).inserted }
    }

    private static func removing(_ pattern: String, from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    /// Các nhóm bắt của mọi lần khớp (nhóm không khớp ⇒ `""`).
    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, options: [], range: NSRange(location: 0, length: source.length)).map { match in
            (1..<max(1, match.numberOfRanges)).map { index in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : source.substring(with: range)
            }
        }
    }
}
