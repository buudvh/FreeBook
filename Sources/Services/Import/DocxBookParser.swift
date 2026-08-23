import Foundation

/// Nhánh DOCX: đọc OOXML (`word/document.xml`) thành danh sách **khối đoạn văn** rồi tách chương theo
/// thứ tự rơi heading → mốc sang trang → quy tắc TOC → một chương.
///
/// Không dùng SwiftSoup ở đây: OOXML là XML chặt chẽ với namespace `w:`, `XMLParser` của Foundation
/// đọc đúng và không phải nạp cả cây DOM. `shouldResolveExternalEntities` để `false` (mặc định, vẫn
/// khai tường minh) và `externalEntityResolvingPolicy = .never` để một file dựng tay không kéo được
/// tài nguyên ngoài.
///
/// Định dạng chữ (in nghiêng, cỡ chữ) bị bỏ — chương lưu là text thuần trong `.bin`. Ảnh trong tài
/// liệu cũng bị bỏ vì Reader không có đường hiển thị ảnh nội tuyến; DOCX không có khái niệm ảnh bìa
/// nên `coverData` luôn `nil`.
enum DocxBookParser {
    static func parse(
        fileUrl: URL,
        fileName: String,
        rules: [TOCRule]? = nil,
        structure: BookImportService.StructureMode = .auto
    ) throws -> ParsedBook {
        let package = try DocxArchiveReader.read(fileUrl: fileUrl)
        let blocks = try blocks(in: package.documentXml)
        guard !blocks.isEmpty else { throw BookImportService.ImportError.emptyContent }

        let meta = metadata(package.coreXml)
        var chapters: [ParserChapter] = []
        var note = ""

        if structure != .tocRules, let byHeading = chaptersByHeading(blocks) {
            chapters = byHeading
            note = "Heading của DOCX — \(byHeading.count) chương"
        } else if structure != .tocRules, let byPage = chaptersByPageBreak(blocks) {
            chapters = byPage
            note = "Mốc sang trang của DOCX — \(byPage.count) chương"
        } else {
            let text = blocks.map(\.text).joined(separator: "\n")
            let parsed = TxtBookParser.parse(content: text, fileName: fileName, rules: rules)
            chapters = parsed.chapters
            note = "Quy tắc TOC — \(parsed.chapters.count) chương"
        }

        if chapters.isEmpty {
            let text = blocks.map(\.text).joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BookImportService.ImportError.emptyContent
            }
            chapters = [ParserChapter(title: meta.title ?? TxtBookParser.bookTitle(fromFileName: fileName), content: text)]
            note = "Không tìm thấy ranh giới chương"
        }

        return ParsedBook(
            title: meta.title ?? TxtBookParser.bookTitle(fromFileName: fileName),
            chapters: chapters,
            author: meta.author,
            structureNote: note
        )
    }

    // MARK: - Tách chương

    /// Heading chỉ được tin khi có **≥ 2** heading và chúng không chiếm quá nửa số đoạn — một tài liệu
    /// gán style Heading cho mọi dòng thì heading không còn mang nghĩa ranh giới chương.
    private static func chaptersByHeading(_ blocks: [Block]) -> [ParserChapter]? {
        let headings = blocks.filter { $0.headingLevel != nil && !$0.text.isEmpty }
        guard headings.count >= 2, headings.count * 2 <= blocks.count else { return nil }

        var chapters: [ParserChapter] = []
        var title = "Mở đầu"
        var body: [String] = []

        for block in blocks {
            if block.headingLevel != nil, !block.text.isEmpty {
                appendChapter(&chapters, title: title, body: body)
                title = block.text
                body = []
            } else if !block.text.isEmpty {
                body.append(block.text)
            }
        }
        appendChapter(&chapters, title: title, body: body)
        return chapters.count >= 2 ? chapters : nil
    }

    /// Mốc sang trang: `<w:br w:type="page"/>`, `<w:pageBreakBefore/>` và `<w:sectPr>` cuối đoạn.
    /// Tiêu đề lấy từ dòng đầu của mảnh khi dòng đó đủ ngắn để là một tiêu đề.
    private static func chaptersByPageBreak(_ blocks: [Block]) -> [ParserChapter]? {
        var segments: [[String]] = []
        var current: [String] = []
        var forceBreak = false

        for block in blocks {
            if (block.pageBreakBefore || forceBreak), !current.isEmpty {
                segments.append(current)
                current = []
            }
            forceBreak = block.pageBreakAfter
            if !block.text.isEmpty { current.append(block.text) }
        }
        if !current.isEmpty { segments.append(current) }
        guard segments.count >= 2 else { return nil }

        var chapters: [ParserChapter] = []
        for (index, lines) in segments.enumerated() {
            var lines = lines
            var title = "Chương \(index + 1)"
            if let first = lines.first, first.count <= 100 {
                title = first
                lines.removeFirst()
            }
            chapters.append(ParserChapter(title: title, content: lines.joined(separator: "\n")))
        }
        return chapters
    }

    /// Giữ đúng quy ước của `TxtBookParser`: phần trước heading đầu tiên chỉ thành chương `"Mở đầu"`
    /// khi thực sự có nội dung.
    private static func appendChapter(_ chapters: inout [ParserChapter], title: String, body: [String]) {
        guard !body.isEmpty || title != "Mở đầu" else { return }
        chapters.append(ParserChapter(title: title, content: body.joined(separator: "\n")))
    }

    // MARK: - Đọc XML

    private static func blocks(in data: Data) throws -> [Block] {
        let collector = BodyCollector()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = collector
        guard parser.parse() else {
            throw BookImportService.ImportError.malformed("word/document.xml sai cú pháp XML")
        }
        return collector.blocks
    }

    private static func metadata(_ data: Data?) -> (title: String?, author: String?) {
        guard let data else { return (nil, nil) }
        let collector = CoreCollector()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = collector
        guard parser.parse() else { return (nil, nil) }
        return (collector.value(collector.title), collector.value(collector.author))
    }

    private static func localName(_ elementName: String) -> String {
        return (elementName.components(separatedBy: ":").last ?? elementName).lowercased()
    }

    /// Một đoạn văn của tài liệu, kèm hai thông tin để tách chương.
    private struct Block {
        let text: String
        /// 1…3 khi đoạn mang style Heading hoặc `outlineLvl` tương ứng; `nil` là đoạn thường.
        let headingLevel: Int?
        let pageBreakBefore: Bool
        let pageBreakAfter: Bool
    }

    /// Delegate cho `word/document.xml`, nest trong enum để file vẫn đúng **một** type top-level.
    private final class BodyCollector: NSObject, XMLParserDelegate {
        var blocks: [Block] = []

        private var text = ""
        private var headingLevel: Int?
        private var breakBefore = false
        private var breakAfter = false
        private var capturing = false
        private var inProperties = false

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch DocxBookParser.localName(elementName) {
            case "p":
                text = ""
                headingLevel = nil
                breakBefore = false
                breakAfter = false
                capturing = false
            case "ppr":
                inProperties = true
            case "pstyle":
                if let level = DocxBookParser.headingLevel(styleName: attributeDict["w:val"]) {
                    headingLevel = level
                }
            case "outlinelvl":
                if let raw = attributeDict["w:val"], let value = Int(raw), value >= 0, value <= 2 {
                    headingLevel = value + 1
                }
            case "pagebreakbefore":
                // `<w:pageBreakBefore w:val="0"/>` là tắt tường minh.
                if attributeDict["w:val"] != "0", attributeDict["w:val"] != "false" {
                    breakBefore = true
                }
            case "sectpr":
                // `<w:sectPr>` trong `<w:pPr>` đánh dấu **kết thúc** section ⇒ đoạn sau sang trang mới.
                if inProperties { breakAfter = true }
            case "br":
                guard attributeDict["w:type"]?.lowercased() == "page" else { return }
                if text.isEmpty { breakBefore = true } else { breakAfter = true }
            case "cr":
                text += "\n"
            case "tab":
                text += " "
            case "t":
                capturing = true
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard capturing else { return }
            text += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            switch DocxBookParser.localName(elementName) {
            case "t":
                capturing = false
            case "ppr":
                inProperties = false
            case "p":
                blocks.append(Block(
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    headingLevel: headingLevel,
                    pageBreakBefore: breakBefore,
                    pageBreakAfter: breakAfter
                ))
                text = ""
                headingLevel = nil
                breakBefore = false
                breakAfter = false
            default:
                break
            }
        }
    }

    /// Delegate cho `docProps/core.xml` (`dc:title`, `dc:creator`).
    private final class CoreCollector: NSObject, XMLParserDelegate {
        var title: String?
        var author: String?

        private var key: String?
        private var buffer = ""

        func value(_ raw: String?) -> String? {
            guard let raw else { return nil }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = DocxBookParser.localName(elementName)
            if name == "title" || name == "creator" {
                key = name
                buffer = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard key != nil else { return }
            buffer += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            guard let key, key == DocxBookParser.localName(elementName) else { return }
            if key == "title", title == nil { title = buffer }
            if key == "creator", author == nil { author = buffer }
            self.key = nil
            buffer = ""
        }
    }

    /// `w:val` của `<w:pStyle>` là **style ID**, không phải tên hiển thị, nên Word bản tiếng nào cũng
    /// ghi `Heading1`; LibreOffice ghi `Heading_20_1`, vài converter ghi `Heading 1`. Vì vậy bỏ khoảng
    /// trắng/gạch dưới rồi so tiền tố `heading` và lấy chữ số cuối. `outlineLvl` là nguồn thứ hai,
    /// độc lập hoàn toàn với tên style.
    private static func headingLevel(styleName: String?) -> Int? {
        guard let styleName else { return nil }
        let compact = styleName.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        guard compact.hasPrefix("heading") else { return nil }
        guard let digit = compact.last, let level = Int(String(digit)), level >= 1, level <= 3 else {
            return nil
        }
        return level
    }
}
