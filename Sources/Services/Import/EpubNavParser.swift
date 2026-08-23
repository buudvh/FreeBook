import Foundation

/// Đọc mục lục thật của EPUB: `toc.ncx` (EPUB2) hoặc tài liệu `nav` (EPUB3).
///
/// Mục lục truyện dài hay để tập/quyển ở cấp 1 và chương ở cấp 2, nên `navPoint` lồng nhau được
/// **flatten theo thứ tự xuất hiện** — bỏ cấp con là mất hết chương.
enum EpubNavParser {
    struct Entry: Sendable {
        let title: String
        /// href nguyên bản trong file mục lục, có thể kèm `#fragment`.
        let rawHref: String

        var path: String {
            return rawHref.components(separatedBy: "#").first ?? rawHref
        }

        var fragment: String? {
            let parts = rawHref.components(separatedBy: "#")
            guard parts.count > 1, !parts[1].isEmpty else { return nil }
            return parts[1].removingPercentEncoding ?? parts[1]
        }
    }

    // MARK: - EPUB2: toc.ncx

    static func parseNcx(data: Data) -> [Entry] {
        let collector = Collector()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = collector
        guard parser.parse() else { return [] }
        return collector.entries
    }

    /// Delegate `XMLParser`, nest trong enum để file vẫn đúng **một** type top-level.
    ///
    /// Máy trạng thái tuần tự: `navPoint` → `navLabel/text` (nhớ tiêu đề) → `content src` (phát Entry).
    /// Vì XML đi theo thứ tự tài liệu, cách này tự nhiên flatten mọi cấp lồng nhau.
    private final class Collector: NSObject, XMLParserDelegate {
        var entries: [Entry] = []

        private var pendingTitle: String?
        private var inNavLabel = false
        private var capturingText = false
        private var currentText = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch localName(elementName) {
            case "navlabel":
                inNavLabel = true
            case "text":
                if inNavLabel {
                    capturingText = true
                    currentText = ""
                }
            case "content":
                guard let src = attributeDict["src"], !src.isEmpty else { return }
                let title = (pendingTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                entries.append(Entry(title: title, rawHref: src))
                pendingTitle = nil
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard capturingText else { return }
            currentText += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            switch localName(elementName) {
            case "text":
                if capturingText {
                    pendingTitle = currentText
                    capturingText = false
                    currentText = ""
                }
            case "navlabel":
                inNavLabel = false
            default:
                break
            }
        }

        private func localName(_ elementName: String) -> String {
            return (elementName.components(separatedBy: ":").last ?? elementName).lowercased()
        }
    }

    // MARK: - EPUB3: nav

    /// Đọc `<nav epub:type="toc">` của tài liệu nav. Selector SwiftSoup không xử lý được tên thuộc
    /// tính có dấu `:` nên khoanh vùng khối `nav` bằng regex rồi mới lấy từng `<a href>`.
    static func parseNav(html: String) -> [Entry] {
        let scope = tocNavBlock(html: html) ?? html
        guard let regex = try? NSRegularExpression(
            pattern: "<a\\b[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>([\\s\\S]*?)</a>",
            options: [.caseInsensitive]
        ) else { return [] }

        let ns = scope as NSString
        return regex.matches(in: scope, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let href = ns.substring(with: match.range(at: 1))
            guard !href.isEmpty, !href.hasPrefix("http") else { return nil }
            let title = XhtmlTextExtractor.inlineText(html: ns.substring(with: match.range(at: 2)))
            return Entry(title: title, rawHref: href)
        }
    }

    private static func tocNavBlock(html: String) -> String? {
        let patterns = [
            "<nav\\b[^>]*epub:type\\s*=\\s*[\"'][^\"']*toc[^\"']*[\"'][^>]*>([\\s\\S]*?)</nav>",
            "<nav\\b[^>]*>([\\s\\S]*?)</nav>"
        ]
        let ns = html as NSString
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length))
            else { continue }
            return ns.substring(with: match.range(at: 1))
        }
        return nil
    }
}
