import Foundation
import SwiftSoup

/// Chế độ mặc định (phương ngữ kiểu jsoup, spec §2.8) và chế độ `@css:` (§2.9) trên SwiftSoup.
///
/// Phần-chọn tách theo `@` ở mức ngoài cùng thành các bước. `getElements`: mọi bước là bước chọn. `getString` /
/// `getStringList`: bước cuối là bước trích (`text`, `ownText`, `textNodes`, `html`, `all`, hoặc tên thuộc tính).
/// Bộ chọn CSS lỗi cú pháp ⇒ bước đó cho danh sách rỗng và báo qua `report`, không ném lỗi.
struct LegadoJsoupSelector {
    /// `true` cho `@css:`: mỗi bước là bộ chọn CSS thuần, không có `class.`/`tag.`/…, không có chỉ số kiểu chấm.
    let cssOnly: Bool
    let report: (String) -> Void

    func elements(_ rule: String, in root: Element) -> [Element] {
        let steps = Self.steps(of: rule)
        var current = [root]
        for step in steps {
            current = select(step, from: current)
            if current.isEmpty { break }
        }
        return current
    }

    func strings(_ rule: String, in root: Element) -> [String] {
        var steps = Self.steps(of: rule)
        guard let extraction = steps.popLast() else { return [] }
        var current = [root]
        for step in steps {
            current = select(step, from: current)
            if current.isEmpty { return [] }
        }
        return current.compactMap { Self.extract(extraction, from: $0) }.filter { !$0.isEmpty }
    }

    static func steps(of rule: String) -> [String] {
        LegadoRuleScanner.split(rule, by: "@")
    }

    // MARK: - Bước chọn (§2.8.2)

    private func select(_ step: String, from elements: [Element]) -> [Element] {
        let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return elements }
        if cssOnly {
            return elements.flatMap { css(trimmed, in: $0) }
        }
        let parsed = LegadoRuleIndex.parse(step: trimmed)
        let body = parsed.body.trimmingCharacters(in: .whitespaces)
        var selected: [Element]
        if body.isEmpty {
            selected = elements
        } else {
            selected = []
            for element in elements {
                selected.append(contentsOf: selectOne(body, in: element))
            }
        }
        if let index = parsed.index {
            selected = index.apply(selected)
        }
        return selected
    }

    private func selectOne(_ body: String, in element: Element) -> [Element] {
        if body == "children" {
            return element.children().array()
        }
        if body.hasPrefix("class.") {
            let names = body.dropFirst("class.".count).split(separator: " ").map(String.init).filter { !$0.isEmpty }
            guard !names.isEmpty else { return [] }
            return allElements(in: element).filter { candidate in names.allSatisfy { candidate.hasClass($0) } }
        }
        if body.hasPrefix("tag.") {
            let name = String(body.dropFirst("tag.".count))
            guard !name.isEmpty else { return [] }
            return (try? element.getElementsByTag(name).array()) ?? []
        }
        if body.hasPrefix("id.") {
            let name = String(body.dropFirst("id.".count))
            return allElements(in: element).filter { $0.id() == name }
        }
        if body.hasPrefix("text.") {
            let needle = String(body.dropFirst("text.".count))
            guard !needle.isEmpty else { return [] }
            return allElements(in: element).filter { $0.ownText().contains(needle) }
        }
        return css(body, in: element)
    }

    private func css(_ query: String, in element: Element) -> [Element] {
        do {
            return try element.select(query).array()
        } catch {
            report("Bộ chọn CSS lỗi `\(query)`: \(error)")
            return []
        }
    }

    private func allElements(in element: Element) -> [Element] {
        (try? element.getAllElements().array()) ?? []
    }

    // MARK: - Bước trích (§2.8.4)

    static func extract(_ keyword: String, from element: Element) -> String? {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case "text":
            return try? element.text()
        case "ownText", "owntext":
            return element.ownText()
        case "textNodes", "textnodes":
            return element.textNodes()
                .map { $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        case "html", "all":
            return try? element.outerHtml()
        case "":
            return try? element.text()
        default:
            return try? element.attr(key)
        }
    }
}
