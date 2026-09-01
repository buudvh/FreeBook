import Foundation
import SwiftSoup

/// Bước **cuối** của một rule jsoup: đổi danh sách element thành danh sách chuỗi.
///
/// Port `AnalyzeByJSoup.getResultLast` (`:229-280`). Ngoài 5 từ khoá cố định, mọi chuỗi khác được coi
/// là **tên attribute** — đây là lý do `@href`, `@src`, `@data-src` chạy được mà không cần khai gì.
public enum LegadoJsoupExtractor {

    public static func extract(_ lastRule: String, from elements: [Element]) -> [String] {
        let rule = lastRule.trimmingCharacters(in: .whitespacesAndNewlines)
        switch rule {
        case "text":
            return elements.compactMap { element in
                guard let text = try? element.text(), !text.isEmpty else { return nil }
                return text
            }

        case "textNodes":
            return elements.compactMap { element in
                let lines = element.textNodes()
                    .map { $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return lines.isEmpty ? nil : lines.joined(separator: "\n")
            }

        case "ownText":
            return elements.compactMap { element in
                let text = element.ownText()
                return text.isEmpty ? nil : text
            }

        case "html":
            // Legado xoá `<script>`/`<style>` trước khi lấy outerHtml. Không sửa DOM ở đây: element gốc
            // còn dùng cho các rule khác của cùng trang, nên lọc bằng regex trên chuỗi kết quả.
            var pieces: [String] = []
            for element in elements {
                guard let html = try? element.outerHtml(), !html.isEmpty else { continue }
                pieces.append(stripScriptAndStyle(html))
            }
            guard !pieces.isEmpty else { return [] }
            return [pieces.joined()]

        case "all":
            let joined = elements.compactMap { try? $0.outerHtml() }.joined()
            return joined.isEmpty ? [] : [joined]

        default:
            var seen = Set<String>()
            var values: [String] = []
            for element in elements {
                guard let value = try? element.attr(rule) else { continue }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !seen.contains(value) else { continue }
                seen.insert(value)
                values.append(value)
            }
            return values
        }
    }

    /// Bước cuối có phải là "lấy giá trị" hay vẫn là selector.
    ///
    /// Dùng để chẩn đoán; Legado luôn coi **đoạn cuối cùng** là bước lấy giá trị.
    public static func isValueKeyword(_ rule: String) -> Bool {
        ["text", "textNodes", "ownText", "html", "all"].contains(rule)
    }

    private static func stripScriptAndStyle(_ html: String) -> String {
        var result = html
        for tag in ["script", "style"] {
            result = result.replacingOccurrences(
                of: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)\\s*>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }
}
