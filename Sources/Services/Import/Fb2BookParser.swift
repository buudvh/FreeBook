import Foundation

/// Nhánh FB2 (FictionBook 2): XML thuần, có sẵn cấu trúc `section` / `title` / `p` nên **không** cần
/// đoán ranh giới chương bằng regex — đây là format có mục lục đáng tin thứ hai sau EPUB.
///
/// An toàn XML (yêu cầu của phase): `shouldResolveExternalEntities = false`,
/// `externalEntityResolvingPolicy = .never`, và file khai `<!ENTITY` bị **từ chối thẳng** thay vì
/// nhờ parser tự chống (billion-laughs). Ảnh bìa chỉ nhận `href` dạng `#id` trỏ vào `<binary>` trong
/// chính file; mọi href kiểu đường dẫn/URL bị bỏ qua nên không có đường đọc file ngoài.
///
/// Thứ tự chương là thứ tự xuất hiện trong `<body>`. Một `section` chứa cả text trực tiếp lẫn
/// `section` con thì phần text trực tiếp được **xả trước** khi mở section con, nên thứ tự đọc không
/// bao giờ bị đảo.
enum Fb2BookParser {
    static func parse(
        data: Data,
        fileName: String,
        rules: [TOCRule]? = nil,
        structure: BookImportService.StructureMode = .auto
    ) throws -> ParsedBook {
        try rejectEntityDeclaration(in: data)

        let collector = Collector()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = collector
        guard parser.parse() else {
            throw BookImportService.ImportError.malformed("file FB2 sai cú pháp XML")
        }

        var chapters = collector.chapters
        var note = "Cấu trúc section của FB2 — \(chapters.count) chương"

        // Sách một khối (không dùng section) hoặc người dùng ép quy tắc TOC.
        if structure == .tocRules || chapters.count < 2 {
            let text = chapters.map { [$0.title, $0.content].joined(separator: "\n") }
                .joined(separator: "\n")
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw BookImportService.ImportError.emptyContent }
            let parsed = TxtBookParser.parse(content: text, fileName: fileName, rules: rules)
            if parsed.chapters.count > chapters.count || structure == .tocRules {
                chapters = parsed.chapters
                note = "Quy tắc TOC — \(parsed.chapters.count) chương"
            }
        }
        guard !chapters.isEmpty else { throw BookImportService.ImportError.emptyContent }

        return ParsedBook(
            title: collector.bookTitle ?? TxtBookParser.bookTitle(fromFileName: fileName),
            chapters: chapters,
            author: collector.authorName,
            desc: collector.annotationText,
            coverData: collector.coverData,
            structureNote: note
        )
    }

    /// FB2 hợp lệ không cần khai entity riêng; file có `<!ENTITY` gần như luôn là bom giải nén hoặc
    /// mưu đọc file ngoài. Chỉ quét phần prolog (8 KB đầu) vì DOCTYPE chỉ được xuất hiện ở đó.
    private static func rejectEntityDeclaration(in data: Data) throws {
        let head = data.prefix(8 * 1024)
        guard let text = String(data: Data(head), encoding: .utf8)
            ?? String(data: Data(head), encoding: .isoLatin1)
        else { return }
        guard !text.uppercased().contains("<!ENTITY") else {
            throw BookImportService.ImportError.malformed("file FB2 khai entity riêng, bị từ chối vì lý do an toàn")
        }
    }

    private static func localName(_ elementName: String) -> String {
        return (elementName.components(separatedBy: ":").last ?? elementName).lowercased()
    }

    /// Chỉ nhận `href` dạng `#id` (trỏ vào `<binary>` cùng file). Trả `nil` cho đường dẫn/URL.
    private static func internalReference(_ attributes: [String: String]) -> String? {
        for (key, value) in attributes where localName(key) == "href" {
            guard value.hasPrefix("#") else { return nil }
            let id = String(value.dropFirst())
            return id.isEmpty ? nil : id
        }
        return nil
    }

    /// Các element mang text của FB2. `<empty-line/>` không nằm ở đây: nó chỉ là khoảng trắng trình bày.
    private static let textElements: Set<String> = ["p", "v", "subtitle", "text-author", "td", "th"]

    /// Delegate `XMLParser`, nest trong enum để file vẫn đúng **một** type top-level.
    private final class Collector: NSObject, XMLParserDelegate {
        var chapters: [ParserChapter] = []
        var bookTitle: String?
        var authorName: String?
        var annotationText: String?
        var coverData: Data?

        /// Một `section` đang mở. `titleUsed` để lần xả thứ hai của cùng section không trùng tiêu đề.
        private struct Frame {
            var title: String?
            var lines: [String] = []
            var titleUsed = false
        }

        private var stack: [Frame] = []
        private var inBody = false
        private var inDescription = false
        private var inTitleInfo = false
        private var inAuthor = false
        private var inCoverpage = false
        private var titleDepth = 0
        private var annotationDepth = 0
        private var annotationLines: [String] = []
        private var nameParts: [String] = []
        private var coverId: String?
        private var binaryId: String?
        private var binaryType: String?
        private var binaryBuffer: String?
        private var buffer: String?
        private var defaultTitleIndex = 0

        // MARK: Bắt đầu element

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch Fb2BookParser.localName(elementName) {
            case "description":
                inDescription = true
            case "title-info":
                inTitleInfo = true
            case "body":
                // `<body name="notes">` là phần chú thích, không phải nội dung truyện.
                inBody = attributeDict["name"] == nil
            case "section":
                guard inBody else { return }
                if !stack.isEmpty { flush(&stack[stack.count - 1]) }
                stack.append(Frame())
            case "title":
                if inBody { titleDepth += 1 }
            case "annotation":
                if inDescription { annotationDepth += 1 }
            case "coverpage":
                inCoverpage = true
            case "image":
                if inCoverpage, coverId == nil {
                    coverId = Fb2BookParser.internalReference(attributeDict)
                }
            case "binary":
                binaryId = attributeDict["id"]
                binaryType = attributeDict["content-type"]
                binaryBuffer = ""
            case "author":
                if inTitleInfo {
                    inAuthor = true
                    nameParts = []
                }
            case "first-name", "middle-name", "last-name", "nickname":
                if inAuthor { buffer = "" }
            case "book-title":
                if inTitleInfo { buffer = "" }
            case let name where Fb2BookParser.textElements.contains(name):
                if inBody || annotationDepth > 0 { buffer = "" }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if binaryBuffer != nil {
                binaryBuffer? += string
                return
            }
            if buffer != nil { buffer? += string }
        }

        // MARK: Kết thúc element

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            switch Fb2BookParser.localName(elementName) {
            case "description":
                inDescription = false
            case "title-info":
                inTitleInfo = false
            case "coverpage":
                inCoverpage = false
            case "body":
                // Text nằm ngoài mọi `section` vẫn phải thành chương, không được rơi mất.
                while !stack.isEmpty {
                    var frame = stack.removeLast()
                    flush(&frame)
                }
                inBody = false
            case "section":
                guard inBody, !stack.isEmpty else { return }
                var frame = stack.removeLast()
                flush(&frame)
            case "title":
                if inBody, titleDepth > 0 { titleDepth -= 1 }
            case "annotation":
                guard annotationDepth > 0 else { return }
                annotationDepth -= 1
                if annotationDepth == 0, annotationText == nil {
                    let text = annotationLines.joined(separator: "\n")
                    annotationText = text.isEmpty ? nil : text
                }
            case "author":
                inAuthor = false
                if authorName == nil {
                    let name = nameParts.joined(separator: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    authorName = name.isEmpty ? nil : name
                }
            case "first-name", "middle-name", "last-name", "nickname":
                if inAuthor, let text = takeBuffer() { nameParts.append(text) }
            case "book-title":
                if inTitleInfo, bookTitle == nil { bookTitle = takeBuffer() }
            case "binary":
                finishBinary()
            case let name where Fb2BookParser.textElements.contains(name):
                guard let text = takeBuffer() else { return }
                if annotationDepth > 0 {
                    annotationLines.append(text)
                } else if inBody {
                    appendToBody(text)
                }
            default:
                break
            }
        }

        // MARK: Gom nội dung

        /// Text trong `<title>` thuộc tiêu đề section đang mở; `<title>` ngay dưới `<body>` (chưa có
        /// section nào) là tiêu đề sách, dùng làm dự phòng khi `description` không khai `book-title`.
        private func appendToBody(_ text: String) {
            if titleDepth > 0 {
                guard !stack.isEmpty else {
                    if bookTitle == nil { bookTitle = text }
                    return
                }
                let existing = stack[stack.count - 1].title
                stack[stack.count - 1].title = existing.map { "\($0) \(text)" } ?? text
                return
            }
            if stack.isEmpty { stack.append(Frame()) }
            stack[stack.count - 1].lines.append(text)
        }

        private func flush(_ frame: inout Frame) {
            guard !frame.lines.isEmpty else { return }
            if frame.title == nil {
                defaultTitleIndex += 1
                frame.title = "Chương \(defaultTitleIndex)"
            }
            let base = frame.title ?? "Chương"
            chapters.append(ParserChapter(
                title: frame.titleUsed ? "\(base) (tiếp)" : base,
                content: frame.lines.joined(separator: "\n")
            ))
            frame.titleUsed = true
            frame.lines = []
        }

        /// Ảnh bìa: ưu tiên `<binary>` có `id` khớp `<coverpage>`; không có thì lấy ảnh đầu tiên.
        private func finishBinary() {
            defer {
                binaryBuffer = nil
                binaryId = nil
                binaryType = nil
            }
            guard let raw = binaryBuffer, !raw.isEmpty else { return }
            let isImage = binaryType?.lowercased().hasPrefix("image/") ?? false
            let matchesCover = coverId != nil && binaryId == coverId
            guard matchesCover || (coverId == nil && coverData == nil && isImage) else { return }
            guard let decoded = Data(base64Encoded: raw, options: .ignoreUnknownCharacters),
                  !decoded.isEmpty
            else { return }
            coverData = decoded
        }

        private func takeBuffer() -> String? {
            defer { buffer = nil }
            guard let raw = buffer else { return nil }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }
}
