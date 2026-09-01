import Foundation

/// Chế độ bóc tách của một đoạn rule (`AnalyzeRule.Mode`, `AnalyzeRule.kt:830`).
public enum LegadoRuleMode {
    /// jsoup: CSS selector thật **hoặc** phương ngữ `class.x.0@tag.a@text` của Legado.
    case standard
    case xpath
    case json
    case js
    case regex
    /// `@webjs:` — chạy trong WebView. Chưa hỗ trợ, giữ case để báo lỗi có tên.
    case webJs

    /// Nhận biết theo **đúng thứ tự** của `AnalyzeRule.SourceRule.init` (`:644-677`).
    /// Trả về chế độ cùng phần rule đã cắt bỏ tiền tố.
    public static func detect(_ raw: String, isJSONResponse: Bool) -> (mode: LegadoRuleMode, rule: String) {
        let rule = raw
        let lower = rule.lowercased()

        if lower.hasPrefix("@css:") {
            return (.standard, rule)
        }
        if rule.hasPrefix("@@") {
            return (.standard, String(rule.dropFirst(2)))
        }
        if lower.hasPrefix("@xpath:") {
            return (.xpath, String(rule.dropFirst(7)))
        }
        if lower.hasPrefix("@json:") {
            return (.json, String(rule.dropFirst(6)))
        }
        if isJSONResponse || rule.hasPrefix("$.") || rule.hasPrefix("$[") {
            return (.json, rule)
        }
        if rule.hasPrefix("/") {
            // Legado coi `/` đầu chuỗi là dấu hiệu XPath, không cần khai `@XPath:`.
            return (.xpath, rule)
        }
        return (.standard, rule)
    }

    public var displayName: String {
        switch self {
        case .standard: return "CSS/jsoup"
        case .xpath: return "XPath"
        case .json: return "JSONPath"
        case .js: return "JavaScript"
        case .regex: return "Regex"
        case .webJs: return "WebJS"
        }
    }
}
