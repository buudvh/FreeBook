import Foundation

/// Biên dịch một chuỗi rule Legado thành danh sách đoạn `LegadoCompiledRule`.
///
/// Tương ứng `AnalyzeRule.splitSourceRule` (`:574-617`) + `SourceRule.init` (`:643-816`), với **một
/// điểm khác có chủ ý**: Legado nội suy `{{…}}` và `@get:{…}` ngay lúc dựng rule, còn ở đây việc đó
/// dời sang lúc chạy (`LegadoRuleEvaluator.interpolate`) để một rule biên dịch **một lần** vẫn dùng
/// được cho nhiều truyện có túi biến khác nhau.
public enum LegadoRuleCompiler {

    /// Cache theo chuỗi rule gốc. Giới hạn để không phình theo số nguồn đã import.
    private static let cache = LegadoRuleCache<[LegadoCompiledRule]>(limit: 512)

    public static func compile(_ raw: String?, isJSONResponse: Bool = false) -> [LegadoCompiledRule] {
        guard let raw, !raw.isEmpty else { return [] }
        let key = (isJSONResponse ? "j|" : "s|") + raw
        if let cached = cache.value(for: key) { return cached }
        let compiled = build(raw, isJSONResponse: isJSONResponse)
        cache.set(compiled, for: key)
        return compiled
    }

    private static func build(_ raw: String, isJSONResponse: Bool) -> [LegadoCompiledRule] {
        var segments: [LegadoCompiledRule] = []
        for piece in splitScriptBlocks(raw) {
            switch piece {
            case .script(let code):
                segments.append(LegadoCompiledRule(mode: .js, rule: code))
            case .webScript(let code):
                segments.append(LegadoCompiledRule(mode: .webJs, rule: code))
            case .plain(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                segments.append(compilePlain(trimmed, isJSONResponse: isJSONResponse))
            }
        }
        return segments
    }

    private static func compilePlain(_ raw: String, isJSONResponse: Bool) -> LegadoCompiledRule {
        var (mode, rule) = LegadoRuleMode.detect(raw, isJSONResponse: isJSONResponse)

        var putMap: [String: String] = [:]
        rule = extractPutRules(rule, into: &putMap)

        // `:` mở đầu ⇒ toàn bộ phần còn lại là regex (`allInOne`, `:580-583`).
        if rule.hasPrefix(":") {
            mode = .regex
            rule = String(rule.dropFirst())
        }

        // Tách `rule##regex##replacement##` — cắt bằng "##", đúng như `:805-816`.
        let parts = rule.components(separatedBy: "##")
        let body = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let replaceRegex = parts.count > 1 ? parts[1] : nil
        let replacement = parts.count > 2 ? parts[2] : ""
        // Chỉ khi có **thành phần thứ tư** mới là "thay lần khớp đầu"; `###` đơn lẻ chỉ tạo
        // replacement = "#". Đây là chi tiết dễ hiểu sai của cú pháp Legado.
        let replaceFirst = parts.count > 3

        return LegadoCompiledRule(
            mode: mode,
            rule: body,
            replaceRegex: replaceRegex,
            replacement: replacement,
            replaceFirstOnly: replaceFirst,
            putMap: putMap
        )
    }

    // MARK: - Tách khối script

    private enum Piece {
        case plain(String)
        case script(String)
        case webScript(String)
    }

    /// Cắt chuỗi tại các khối `<js>…</js>`, `@js:…`, `@webjs:…`.
    ///
    /// `AppPattern.JS_PATTERN` là `<js>([\w\W]*?)</js>|@js:([\w\W]*)` — nhánh `@js:` **ăn tới hết
    /// chuỗi**, nên không có phần plain nào sau nó.
    private static func splitScriptBlocks(_ raw: String) -> [Piece] {
        var pieces: [Piece] = []
        var remainder = Substring(raw)

        while !remainder.isEmpty {
            let openTag = remainder.range(of: "<js>", options: .caseInsensitive)
            let atJs = remainder.range(of: "@js:", options: .caseInsensitive)
            let atWebJs = remainder.range(of: "@webjs:", options: .caseInsensitive)

            let candidates = [openTag, atJs, atWebJs].compactMap { $0 }
            guard let earliest = candidates.min(by: { $0.lowerBound < $1.lowerBound }) else {
                pieces.append(.plain(String(remainder)))
                break
            }

            if earliest.lowerBound > remainder.startIndex {
                pieces.append(.plain(String(remainder[remainder.startIndex..<earliest.lowerBound])))
            }

            if let openTag, openTag.lowerBound == earliest.lowerBound {
                let tail = remainder[openTag.upperBound...]
                if let closeTag = tail.range(of: "</js>", options: .caseInsensitive) {
                    pieces.append(.script(String(tail[tail.startIndex..<closeTag.lowerBound])))
                    remainder = tail[closeTag.upperBound...]
                } else {
                    // Thiếu thẻ đóng: coi phần còn lại là script, giống hành vi khoan dung của regex.
                    pieces.append(.script(String(tail)))
                    remainder = Substring("")
                }
                continue
            }

            if let atWebJs, atWebJs.lowerBound == earliest.lowerBound {
                pieces.append(.webScript(String(remainder[atWebJs.upperBound...])))
                break
            }

            if let atJs, atJs.lowerBound == earliest.lowerBound {
                pieces.append(.script(String(remainder[atJs.upperBound...])))
                break
            }
        }

        return pieces
    }

    // MARK: - @put

    /// Bóc mọi `@put:{key:rule}` khỏi chuỗi, nạp vào `putMap` (`putPattern`, `:989`).
    ///
    /// JSON bên trong **không chuẩn**: khoá thường không có nháy (`@put:{bookId:$.id}`), nên phải tự
    /// phân tích thay vì `JSONSerialization`.
    private static func extractPutRules(_ raw: String, into putMap: inout [String: String]) -> String {
        var result = raw
        while let marker = result.range(of: "@put:", options: .caseInsensitive) {
            let tail = result[marker.upperBound...]
            guard tail.first == "{", let closeIndex = matchingBrace(in: tail) else { break }
            let body = tail[tail.index(after: tail.startIndex)..<closeIndex]
            for (key, value) in parsePutBody(String(body)) {
                putMap[key] = value
            }
            result.removeSubrange(marker.lowerBound..<tail.index(after: closeIndex))
        }
        return result
    }

    private static func matchingBrace(in text: Substring) -> Substring.Index? {
        var scanner = BalanceScanner()
        var index = text.startIndex
        var started = false
        while index < text.endIndex {
            let scalar = text[index].unicodeScalars.first ?? " "
            scanner.consume(scalar)
            if scalar == "{" { started = true }
            if started && scanner.isBalanced { return index }
            index = text.index(after: index)
        }
        return nil
    }

    private static func parsePutBody(_ body: String) -> [String: String] {
        var map: [String: String] = [:]
        for entry in LegadoRuleLexer.split(body, separator: ",") {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let separator = firstTopLevelColon(in: trimmed) else { continue }
            let key = unquote(String(trimmed[trimmed.startIndex..<separator]))
            let value = unquote(String(trimmed[trimmed.index(after: separator)...]))
            guard !key.isEmpty, !value.isEmpty else { continue }
            map[key] = value
        }
        return map
    }

    private static func firstTopLevelColon(in text: String) -> String.Index? {
        var scanner = BalanceScanner()
        var index = text.startIndex
        while index < text.endIndex {
            let scalar = text[index].unicodeScalars.first ?? " "
            if scanner.isAtTopLevel, scalar == ":" { return index }
            scanner.consume(scalar)
            index = text.index(after: index)
        }
        return nil
    }

    private static func unquote(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2 {
            let first = trimmed.first
            let last = trimmed.last
            if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                trimmed = String(trimmed.dropFirst().dropLast())
            }
        }
        return trimmed
    }
}
