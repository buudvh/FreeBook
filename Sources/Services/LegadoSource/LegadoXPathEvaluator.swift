import Foundation
import SwiftSoup

/// Thực thi XPath (tập con) trên cây SwiftSoup.
///
/// Legado dùng `org.seimicrawler.xpath` chạy trên DOM jsoup. Ở đây **không** dùng libxml2: nó cần
/// module map riêng cho Swift và không kiểm chứng được trên máy Windows, trong khi tập XPath mà nguồn
/// truyện dùng thật rất hẹp (`//div[@class='x']/a/@href`, `//*[@id="y"]//text()`). Đánh đổi: biểu thức
/// vượt tập con bị từ chối tường minh qua `LegadoUnsupportedFeature.xpathBeyondSubset`.
public enum LegadoXPathEvaluator {

    public struct Outcome {
        public let strings: [String]
        public let elements: [Element]
        public let usedUnsupportedSyntax: Bool

        public init(strings: [String], elements: [Element], usedUnsupportedSyntax: Bool) {
            self.strings = strings
            self.elements = elements
            self.usedUnsupportedSyntax = usedUnsupportedSyntax
        }
    }

    public static func evaluate(_ expression: String, on root: Element) -> Outcome {
        let steps = LegadoXPathParser.parse(expression)
        guard !steps.isEmpty else {
            return Outcome(strings: [], elements: [], usedUnsupportedSyntax: false)
        }
        let unsupported = steps.contains { $0.hasUnsupportedPredicate }

        var currentElements: [Element] = [root]
        var strings: [String] = []

        for (offset, step) in steps.enumerated() {
            let isLast = offset == steps.count - 1

            switch step.nodeTest {
            case .attribute(let name):
                strings = currentElements.compactMap { element in
                    guard let value = try? element.attr(name) else { return nil }
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : value
                }
                currentElements = []

            case .text:
                strings = currentElements.flatMap { element -> [String] in
                    let nodes = element.textNodes()
                        .map { $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if !nodes.isEmpty { return nodes }
                    // `//x//text()` trên thẻ chỉ có con: lấy text gộp để không mất nội dung.
                    if step.axis == .descendant, let text = try? element.text(), !text.isEmpty {
                        return [text]
                    }
                    return []
                }
                currentElements = []

            case .element, .anyElement:
                var found = candidates(for: step, in: currentElements)
                found = applyPredicates(step.predicates, to: found)
                currentElements = found
                if isLast {
                    strings = currentElements.compactMap { try? $0.text() }.filter { !$0.isEmpty }
                }
            }

            if currentElements.isEmpty && !isLast && strings.isEmpty {
                break
            }
        }

        return Outcome(
            strings: strings,
            elements: currentElements,
            usedUnsupportedSyntax: unsupported
        )
    }

    private static func candidates(
        for step: LegadoXPathStep,
        in elements: [Element]
    ) -> [Element] {
        var result: [Element] = []
        for element in elements {
            switch (step.axis, step.nodeTest) {
            case (.child, .element(let name)):
                result.append(contentsOf: element.children().array().filter {
                    $0.tagName().lowercased() == name.lowercased()
                })
            case (.child, .anyElement):
                result.append(contentsOf: element.children().array())
            case (.descendant, .element(let name)):
                if let found = try? element.getElementsByTag(name) {
                    result.append(contentsOf: found.array())
                }
            case (.descendant, .anyElement):
                if let found = try? element.select("*") {
                    result.append(contentsOf: found.array())
                }
            default:
                break
            }
        }
        return result
    }

    private static func applyPredicates(
        _ predicates: [LegadoXPathStep.Predicate],
        to elements: [Element]
    ) -> [Element] {
        var current = elements
        for predicate in predicates {
            switch predicate {
            case .position(let position):
                // XPath đánh số từ 1.
                let index = position - 1
                current = (index >= 0 && index < current.count) ? [current[index]] : []

            case .last:
                current = current.isEmpty ? [] : [current[current.count - 1]]

            case .hasAttribute(let name):
                current = current.filter { element in
                    guard let value = try? element.attr(name) else { return false }
                    return !value.isEmpty
                }

            case .attributeEquals(let name, let expected, let negated):
                current = current.filter { element in
                    let value = (try? element.attr(name)) ?? ""
                    return negated ? value != expected : value == expected
                }

            case .contains(let target, let expected):
                current = current.filter { element in
                    value(of: target, in: element).contains(expected)
                }

            case .startsWith(let target, let expected):
                current = current.filter { element in
                    value(of: target, in: element).hasPrefix(expected)
                }

            case .unsupported:
                // Không lọc gì để tránh trả rỗng vô cớ; cờ `usedUnsupportedSyntax` đã báo cho caller.
                break
            }
            if current.isEmpty { break }
        }
        return current
    }

    private static func value(of target: LegadoXPathStep.Target, in element: Element) -> String {
        switch target {
        case .attribute(let name):
            return (try? element.attr(name)) ?? ""
        case .text:
            return (try? element.text()) ?? ""
        }
    }
}
