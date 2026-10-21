import Foundation
import SwiftSoup

/// "Nội dung hiện hành" mà một rule được áp lên (spec §0.6, §2.1), cũng là kiểu của **mục** trong danh sách
/// (`bookList`, `chapterList`…) mà Agent luồng truyền lại cho `LegadoRuleAnalyzer.string(_:in:)`.
///
/// Chỉ dùng trên thread engine (phần tử SwiftSoup và nút libxml2 không an toàn đa luồng).
enum LegadoContentNode {
    case null
    case string(String)
    /// Tài liệu hoặc phần tử HTML (SwiftSoup; `Document` là một `Element`).
    case html(Element)
    case xpath(LegadoXPathNode)
    case json(LegadoEngineJSON)
    /// Mục của regex danh sách `:` — `[0]` là cả đoạn khớp, `[n]` là nhóm n (§2.13).
    case regexMatch([String])
    case list([LegadoContentNode])

    // MARK: - Dựng

    /// Nội dung từ thân phản hồi: JSON nếu thân bắt đầu bằng `{`/`[` và parse được, ngược lại tài liệu HTML.
    static func from(body: String, baseUrl: String) -> LegadoContentNode {
        if let json = LegadoEngineJSONParser.parseContainer(body) {
            return .json(json)
        }
        if let document = try? SwiftSoup.parse(body, baseUrl) {
            return .html(document)
        }
        return .string(body)
    }

    // MARK: - Chuyển đổi

    /// Chuỗi nguồn: phần tử → outer HTML, JSON → văn bản JSON (chuỗi JSON giữ nguyên), chuỗi → chính nó.
    /// Dùng cho đuôi regex khi phần-chọn rỗng (§2.6) và regex danh sách (§2.13).
    var sourceText: String {
        switch self {
        case .null: return ""
        case .string(let text): return text
        case .html(let element):
            if let document = element as? Document { return (try? document.outerHtml()) ?? "" }
            return (try? element.outerHtml()) ?? ""
        case .xpath(let node): return node.outerHTML
        case .json(let value):
            if case .string(let text) = value { return text }
            return value.compactText
        case .regexMatch(let groups): return groups.first ?? ""
        case .list(let items): return items.map { $0.sourceText }.joined(separator: "\n")
        }
    }

    /// Chuỗi khi nội dung là **kết quả cuối** của `getString` (§2.14): phần tử → chữ, JSON → chuỗi vô hướng/văn bản JSON.
    var displayText: String {
        switch self {
        case .null: return ""
        case .string(let text): return text
        case .html(let element): return (try? element.text()) ?? ""
        case .xpath(let node): return node.textContent
        case .json(let value): return value.scalarString
        case .regexMatch(let groups): return groups.first ?? ""
        case .list(let items): return items.map { $0.displayText }.joined(separator: "\n")
        }
    }

    /// Giá trị JSON nếu nội dung là JSON, chuỗi JSON object/mảng, hoặc danh sách gồm toàn giá trị JSON/chuỗi.
    var jsonValue: LegadoEngineJSON? {
        switch self {
        case .json(let value): return value
        case .string(let text): return LegadoEngineJSONParser.parseContainer(text)
        case .list(let items):
            var values: [LegadoEngineJSON] = []
            for item in items {
                switch item {
                case .json(let value): values.append(value)
                case .string(let text): values.append(LegadoEngineJSONParser.parseContainer(text) ?? .string(text))
                case .null: values.append(.null)
                default: return nil
                }
            }
            return .array(values)
        default:
            return nil
        }
    }

    var isJSONLike: Bool {
        switch self {
        case .json: return true
        case .string(let text): return LegadoEngineJSONParser.parseContainer(text) != nil
        default: return false
        }
    }

    var isXPathNode: Bool {
        if case .xpath = self { return true }
        return false
    }

    /// Phần tử SwiftSoup để chạy chế độ mặc định/CSS. Nút XPath được tuần tự hoá rồi parse lại (§2.12).
    func htmlElement(baseUrl: String) -> Element? {
        switch self {
        case .html(let element):
            return element
        case .xpath(let node):
            return Self.fragmentElement(node.outerHTML, baseUrl: baseUrl, expectedTag: node.tagName)
        case .string(let text):
            return try? SwiftSoup.parse(text, baseUrl)
        case .json(let value):
            return try? SwiftSoup.parse(value.scalarString, baseUrl)
        case .regexMatch(let groups):
            return try? SwiftSoup.parse(groups.first ?? "", baseUrl)
        case .null, .list:
            return nil
        }
    }

    /// Mảnh HTML của **một** phần tử: trả chính phần tử đó (không phải `body` bọc ngoài).
    static func fragmentElement(_ html: String, baseUrl: String, expectedTag: String?) -> Element? {
        let tag = expectedTag?.lowercased() ?? ""
        if tag == "html" || tag == "head" || tag == "body" {
            guard let document = try? SwiftSoup.parse(html, baseUrl) else { return nil }
            if tag == "head" { return document.head() }
            if tag == "body" { return document.body() }
            return document
        }
        guard let document = try? SwiftSoup.parseBodyFragment(html, baseUrl), let body = document.body() else {
            return nil
        }
        let children = body.children()
        if children.size() == 1 { return children.get(0) }
        return body
    }

    // MARK: - Kết quả cuối theo dạng yêu cầu (§2.14)

    var finalString: String {
        displayText
    }

    var finalElements: [LegadoContentNode] {
        switch self {
        case .null:
            return []
        case .string(let text):
            if let json = LegadoEngineJSONParser.parseContainer(text), case .array(let items) = json {
                return items.map { LegadoContentNode.json($0) }
            }
            return text.isEmpty ? [] : [.string(text)]
        case .json(let value):
            switch value {
            case .array(let items): return items.map { LegadoContentNode.json($0) }
            case .null: return []
            default: return [.json(value)]
            }
        case .list(let items):
            return items
        default:
            return [self]
        }
    }

    var finalStrings: [String] {
        switch self {
        case .null:
            return []
        case .string(let text):
            if let json = LegadoEngineJSONParser.parseContainer(text), case .array(let items) = json {
                return items.map { $0.scalarString }.filter { !$0.isEmpty }
            }
            return text.isEmpty ? [] : [text]
        case .json(let value):
            if case .array(let items) = value { return items.map { $0.scalarString }.filter { !$0.isEmpty } }
            let text = value.scalarString
            return text.isEmpty ? [] : [text]
        case .list(let items):
            return items.map { $0.displayText }.filter { !$0.isEmpty }
        default:
            let text = displayText
            return text.isEmpty ? [] : [text]
        }
    }

    /// Rỗng theo nghĩa của `||` trên danh sách / chuỗi.
    var isEmptyResult: Bool {
        switch self {
        case .null: return true
        case .string(let text): return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .list(let items): return items.isEmpty
        case .json(let value):
            if case .array(let items) = value { return items.isEmpty }
            return value.isNull
        default: return false
        }
    }
}
