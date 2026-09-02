import Foundation
import SwiftSoup

/// Dữ liệu vào của một lượt bóc tách: cây HTML, JSON đã parse, hoặc chuỗi thô.
///
/// Legado giữ `Any` rồi ép kiểu lại ở từng chế độ (`getAnalyzeByJSoup(result)`…). Ở đây dùng enum để
/// việc ép kiểu là tường minh và không im lặng trả rỗng khi kiểu không khớp.
public enum LegadoRuleContext {
    case html(Element)
    case json(Any)
    case text(String)

    /// Ngữ cảnh hiện tại là JSON.
    ///
    /// Quan trọng cho việc chọn chế độ: trong Legado, khi dữ liệu đang là JSON thì một rule **trần**
    /// (`title`, `url`) là JSONPath chứ không phải selector — `AnalyzeRule.SourceRule.init` xét
    /// `isJSON || ruleStr.startsWith("$.")`. Cờ này để `LegadoRuleEvaluator` quyết định đúng ở từng
    /// bước, thay vì chỉ xét một lần theo phản hồi HTTP.
    public var isJSON: Bool {
        if case .json = self { return true }
        return false
    }

    /// Chuỗi tương ứng — dùng khi bước sau cần chuỗi (regex, JS, hoặc re-parse).
    public var stringValue: String {
        switch self {
        case .html(let element):
            return (try? element.outerHtml()) ?? ""
        case .json(let value):
            if let text = value as? String { return text }
            return LegadoJSON.encode(value) ?? ""
        case .text(let text):
            return text
        }
    }

    /// Cây HTML tương ứng; chuỗi/JSON được parse lại.
    public var htmlElement: Element? {
        switch self {
        case .html(let element):
            return element
        case .json(let value):
            guard let text = value as? String else { return nil }
            return try? SwiftSoup.parse(text)
        case .text(let text):
            return try? SwiftSoup.parse(text)
        }
    }

    /// JSON tương ứng; chuỗi được parse lại.
    public var jsonValue: Any? {
        switch self {
        case .json(let value):
            return value
        case .text(let text):
            guard let data = text.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        case .html(let element):
            guard let text = try? element.text(), let data = text.data(using: .utf8) else {
                return nil
            }
            return try? JSONSerialization.jsonObject(with: data)
        }
    }

    /// Tạo ngữ cảnh từ phản hồi HTTP: JSON thì giữ JSON, còn lại parse HTML.
    public static func from(_ response: LegadoHTTPResponse) -> LegadoRuleContext {
        if response.looksLikeJSON, let json = response.jsonObject {
            return .json(json)
        }
        if let document = try? SwiftSoup.parse(response.body, response.finalUrl) {
            return .html(document)
        }
        return .text(response.body)
    }

    /// Tạo ngữ cảnh từ một chuỗi bất kỳ, tự nhận JSON.
    public static func from(string raw: String, baseUrl: String = "") -> LegadoRuleContext {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let data = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                return .json(json)
            }
        }
        if let document = try? SwiftSoup.parse(raw, baseUrl) {
            return .html(document)
        }
        return .text(raw)
    }
}
