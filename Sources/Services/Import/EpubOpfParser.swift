import Foundation

/// Đọc file OPF của EPUB: metadata `dc:*`, manifest (danh sách file) và spine (thứ tự đọc).
///
/// Dùng `XMLParser` của Foundation, không thêm thư viện. `shouldProcessNamespaces` để `false` nên
/// tên element về nguyên dạng có prefix (`dc:title`) — cắt prefix bằng `localName(_:)`.
enum EpubOpfParser {
    struct Item: Sendable {
        let id: String
        let href: String
        let mediaType: String
        let properties: String
    }

    struct Manifest: Sendable {
        let title: String?
        let author: String?
        let desc: String?
        let items: [String: Item]
        /// `idref` của spine theo đúng thứ tự đọc.
        let spine: [String]
        /// Id item ảnh bìa: `<meta name="cover">` (EPUB2) hoặc `properties` chứa `cover-image` (EPUB3).
        let coverId: String?
        /// Id item `toc.ncx` (EPUB2), lấy từ thuộc tính `toc` của `<spine>`.
        let ncxId: String?
        /// Id item nav (EPUB3), là item có `properties` chứa `nav`.
        let navId: String?
    }

    static func parse(opfURL: URL) throws -> Manifest {
        guard let data = try? Data(contentsOf: opfURL) else {
            throw BookImportService.ImportError.malformed("không đọc được file OPF")
        }

        let collector = Collector()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = collector
        guard parser.parse() else {
            throw BookImportService.ImportError.malformed("file OPF sai cú pháp XML")
        }

        var coverId = collector.metaCoverId
        if coverId == nil {
            coverId = collector.items.values.first { $0.properties.contains("cover-image") }?.id
        }
        let navId = collector.items.values.first { $0.properties.contains("nav") }?.id

        return Manifest(
            title: collector.trimmed(collector.title),
            author: collector.trimmed(collector.author),
            desc: collector.trimmed(collector.desc),
            items: collector.items,
            spine: collector.spine,
            coverId: coverId,
            ncxId: collector.spineTocId,
            navId: navId
        )
    }

    private static func localName(_ elementName: String) -> String {
        return (elementName.components(separatedBy: ":").last ?? elementName).lowercased()
    }

    /// Delegate `XMLParser`, nest trong enum để file vẫn đúng **một** type top-level.
    private final class Collector: NSObject, XMLParserDelegate {
        var title: String?
        var author: String?
        var desc: String?
        var items: [String: Item] = [:]
        var spine: [String] = []
        var spineTocId: String?
        var metaCoverId: String?

        private var currentText: String = ""
        private var capturingKey: String?

        func trimmed(_ value: String?) -> String? {
            guard let value else { return nil }
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = EpubOpfParser.localName(elementName)
            switch name {
            case "title", "creator", "description":
                capturingKey = name
                currentText = ""
            case "item":
                guard let id = attributeDict["id"], let href = attributeDict["href"] else { return }
                items[id] = Item(
                    id: id,
                    href: href,
                    mediaType: attributeDict["media-type"] ?? "",
                    properties: attributeDict["properties"] ?? ""
                )
            case "itemref":
                if let idref = attributeDict["idref"] {
                    spine.append(idref)
                }
            case "spine":
                spineTocId = attributeDict["toc"]
            case "meta":
                if attributeDict["name"]?.lowercased() == "cover" {
                    metaCoverId = attributeDict["content"]
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard capturingKey != nil else { return }
            currentText += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = EpubOpfParser.localName(elementName)
            guard let key = capturingKey, key == name else { return }
            switch key {
            case "title":
                if title == nil { title = currentText }
            case "creator":
                if author == nil { author = currentText }
            case "description":
                if desc == nil { desc = currentText }
            default:
                break
            }
            capturingKey = nil
            currentText = ""
        }
    }
}
