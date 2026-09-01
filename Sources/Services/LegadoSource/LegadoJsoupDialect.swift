import Foundation
import SwiftSoup

/// Thực thi một **bước** rule jsoup của Legado trên một element.
///
/// Port `AnalyzeByJSoup.ElementsSingle.getElementsSingle` (`:303-322`). Legado chỉ nhận 5 tiền tố đặc
/// biệt (`children`, `class`, `tag`, `id`, `text`); mọi thứ khác rơi về `select()` — tức CSS selector
/// thật. Đo trên nguồn thực tế thì nhánh CSS mới là nhánh phổ biến (62% nguồn có dùng phương ngữ,
/// nhưng phần lớn rule vẫn là selector thuần kiểu `.kv a`, `#content`, `ul.chapter-list li a`).
///
/// SwiftSoup là bản port jsoup nên hỗ trợ luôn cả pseudo-selector mà nguồn thật hay dùng
/// (`:contains(…)`, `:eq(n)`, `[attr]`), không cần tự cài.
public enum LegadoJsoupDialect {

    /// Áp một bước rule lên một element, trả về danh sách element kết quả.
    public static func step(_ rule: String, on element: Element) -> [Element] {
        let selector = LegadoIndexSelector.parse(rule)
        let base = baseElements(selector.beforeRule, on: element)

        switch selector.filter {
        case .none:
            return base
        case .select:
            let indexes = selector.resolvedIndexes(count: base.count)
            return indexes.map { base[$0] }
        case .exclude:
            let indexes = Set(selector.resolvedIndexes(count: base.count))
            guard !indexes.isEmpty else { return base }
            return base.enumerated().compactMap { indexes.contains($0.offset) ? nil : $0.element }
        }
    }

    /// Áp một chuỗi bước ngăn bằng `@` (đã cắt sẵn) lên một element.
    public static func steps(_ rules: [String], on element: Element) -> [Element] {
        var current: [Element] = [element]
        for rule in rules {
            let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            var next: [Element] = []
            for item in current {
                next.append(contentsOf: step(trimmed, on: item))
            }
            current = next
            if current.isEmpty { break }
        }
        return current
    }

    private static func baseElements(_ rule: String, on element: Element) -> [Element] {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        // Chỉ số đứng một mình (`[0]`, `.1`) ⇒ lấy các con trực tiếp, giống `children`.
        if trimmed.isEmpty {
            return element.children().array()
        }

        let components = trimmed.components(separatedBy: ".")
        if components.count >= 2 {
            let keyword = components[0].lowercased()
            let argument = components[1]
            switch keyword {
            case "children":
                return element.children().array()
            case "class":
                return (try? element.getElementsByClass(argument))?.array() ?? []
            case "tag":
                return (try? element.getElementsByTag(argument))?.array() ?? []
            case "id":
                // `try?` đã làm phẳng `Element?` của SwiftSoup, nên chỉ cần một lần `if let`.
                if let found = try? element.getElementById(argument) {
                    return [found]
                }
                return []
            case "text":
                return (try? element.getElementsContainingOwnText(argument))?.array() ?? []
            default:
                break
            }
        } else if trimmed.lowercased() == "children" {
            return element.children().array()
        }

        return (try? element.select(trimmed))?.array() ?? []
    }
}
