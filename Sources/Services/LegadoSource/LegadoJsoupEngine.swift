import Foundation
import SwiftSoup

/// Chế độ `Default` — bóc tách bằng jsoup/CSS. Port `AnalyzeByJSoup`.
///
/// Ba toán tử ghép (`:88`, `:110-122`):
/// * `&&` — nối kết quả của mọi nhánh.
/// * `||` — lấy nhánh **đầu tiên** có kết quả rồi dừng.
/// * `%%` — xen kẽ theo chỉ số: nhánh1[0], nhánh2[0], nhánh1[1], nhánh2[1]…
public enum LegadoJsoupEngine {

    public static func stringList(rule: String, on element: Element) -> [String] {
        let (isCss, body) = normalize(rule)
        guard !body.isEmpty else { return [] }

        let (parts, separator) = LegadoRuleLexer.split(body, separators: ["&&", "||", "%%"])
        var branches: [[String]] = []

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let values = isCss
                ? cssBranch(trimmed, on: element)
                : dialectBranch(trimmed, on: element)
            if !values.isEmpty {
                branches.append(values)
                if separator == "||" { break }
            }
        }
        return combine(branches, separator: separator)
    }

    /// Ghép danh sách kết quả thành một chuỗi — `AnalyzeByJSoup.getString` (`:48-60`) nối bằng `\n`.
    public static func string(rule: String, on element: Element) -> String? {
        let list = stringList(rule: rule, on: element)
        if list.isEmpty { return nil }
        if list.count == 1 { return list[0] }
        return list.joined(separator: "\n")
    }

    public static func elements(rule: String, on element: Element) -> [Element] {
        let (isCss, body) = normalize(rule)
        guard !body.isEmpty else { return [] }

        let (parts, separator) = LegadoRuleLexer.split(body, separators: ["&&", "||", "%%"])
        var branches: [[Element]] = []

        for part in parts {
            let trimmed = LegadoRuleLexer.trimLeading(
                part.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard !trimmed.isEmpty else { continue }
            let found: [Element]
            if isCss {
                found = (try? element.select(trimmed))?.array() ?? []
            } else {
                let steps = LegadoRuleLexer.split(trimmed, separator: "@")
                found = LegadoJsoupDialect.steps(steps, on: element)
            }
            if !found.isEmpty {
                branches.append(found)
                if separator == "||" { break }
            }
        }
        return combine(branches, separator: separator)
    }

    // MARK: - Nhánh

    /// `@CSS:` — mọi thứ trước dấu `@` **cuối cùng** là selector, phần sau là bước lấy giá trị
    /// (`:94-99`).
    private static func cssBranch(_ rule: String, on element: Element) -> [String] {
        guard let lastAt = rule.lastIndex(of: "@") else {
            let found = (try? element.select(rule))?.array() ?? []
            return LegadoJsoupExtractor.extract("text", from: found)
        }
        let selector = String(rule[rule.startIndex..<lastAt])
        let valueRule = String(rule[rule.index(after: lastAt)...])
        let found = (try? element.select(selector))?.array() ?? []
        return LegadoJsoupExtractor.extract(valueRule, from: found)
    }

    /// Phương ngữ mặc định: cắt theo `@`, mọi đoạn trừ đoạn cuối là bước chọn element (`:200-224`).
    private static func dialectBranch(_ rule: String, on element: Element) -> [String] {
        let trimmed = LegadoRuleLexer.trimLeading(rule)
        var steps = LegadoRuleLexer.split(trimmed, separator: "@")
        guard let lastRule = steps.popLast() else { return [] }
        let elements = steps.isEmpty
            ? [element]
            : LegadoJsoupDialect.steps(steps, on: element)
        guard !elements.isEmpty else { return [] }
        return LegadoJsoupExtractor.extract(lastRule, from: elements)
    }

    // MARK: - Tiện ích

    private static func normalize(_ rule: String) -> (isCss: Bool, body: String) {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("@css:") {
            return (true, String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (false, trimmed)
    }

    private static func combine<T>(_ branches: [[T]], separator: String?) -> [T] {
        guard !branches.isEmpty else { return [] }
        guard separator == "%%" else {
            return branches.flatMap { $0 }
        }
        var result: [T] = []
        // Legado lấy chỉ số theo **nhánh đầu tiên** (`results[0].indices`), không phải nhánh dài
        // nhất — nhánh sau dài hơn thì phần dư bị bỏ.
        let driverCount = branches[0].count
        for index in 0..<driverCount {
            for branch in branches where index < branch.count {
                result.append(branch[index])
            }
        }
        return result
    }
}
