import Foundation

/// Xuất EPUB 3: `mimetype` → `META-INF/container.xml` → mỗi chương một XHTML (ghi ngay khi có nội dung)
/// → `style.css`, bìa, `nav.xhtml` và `content.opf` ở `finish()`.
///
/// Mục lục và manifest phải biết **toàn bộ** chương nên chỉ dựng được ở cuối; trong lúc chạy renderer chỉ
/// giữ danh sách (id, href, tiêu đề) — vài chục byte mỗi chương, không phải nội dung. Nội dung chương đi
/// thẳng vào archive theo từng entry nên đỉnh RAM bằng một chương.
final class EpubExportRenderer: ExportRenderer {
    private struct ChapterRef {
        let id: String
        let href: String
        let title: String
    }

    private static let contentDirectory = "OEBPS"

    private let request: BookExportRequest
    private let archive: ZipStoreWriter
    private var chapterRefs: [ChapterRef] = []
    private let identifier: String
    private var hasCover: Bool

    var writtenChapterCount: Int { chapterRefs.count }
    var hasContent: Bool { !chapterRefs.isEmpty }

    init(request: BookExportRequest) throws {
        self.request = request
        self.identifier = "urn:uuid:\(UUID().uuidString.lowercased())"
        self.hasCover = (request.coverJpegData?.isEmpty == false)

        let target = try ExportFileNaming.targetURL(bookTitle: request.bookTitle, format: .epub3)
        archive = ZipStoreWriter(staging: try ExportStagingFile(targetURL: target))

        // `mimetype` bắt buộc là entry đầu tiên và không nén — điều kiện nhận dạng EPUB của máy đọc.
        try archive.addEntry(name: "mimetype", text: "application/epub+zip")
        try archive.addEntry(name: "META-INF/container.xml", text: Self.containerXml)
    }

    func append(_ chapter: ExportChapterPayload) throws {
        let index = chapterRefs.count + 1
        let href = String(format: "chapter-%04d.xhtml", index)
        let title = ExportTextEscaper.xml(chapter.title)

        var body = "<section epub:type=\"chapter\">\n<h1>\(title)</h1>\n"
        for paragraph in ExportParagraphSplitter.paragraphs(from: chapter.content) {
            body += "<p>\(ExportTextEscaper.xml(paragraph))</p>\n"
        }
        body += "</section>\n"

        try archive.addEntry(name: "\(Self.contentDirectory)/\(href)", text: Self.xhtml(title: title, body: body))
        chapterRefs.append(ChapterRef(id: "chap\(index)", href: href, title: title))
    }

    func finish() throws -> ExportArtifact {
        guard hasContent else {
            archive.discard()
            throw ExportRenderError.emptyExport
        }

        try archive.addEntry(name: "\(Self.contentDirectory)/style.css", text: Self.styleCss)
        if let cover = request.coverJpegData, !cover.isEmpty {
            try archive.addEntry(name: "\(Self.contentDirectory)/cover.jpg", data: cover)
            try archive.addEntry(name: "\(Self.contentDirectory)/cover.xhtml", text: coverXhtml())
        } else {
            hasCover = false
        }
        try archive.addEntry(name: "\(Self.contentDirectory)/nav.xhtml", text: navXhtml())
        try archive.addEntry(name: "\(Self.contentDirectory)/content.opf", text: opfXml())

        let url = try archive.finish()
        return ExportArtifact(fileURL: url, format: .epub3, chapterCount: chapterRefs.count)
    }

    func discard() {
        archive.discard()
    }

    // MARK: - Khuôn XML

    private static let containerXml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
    </rootfiles>
    </container>
    """

    private static let styleCss = """
    body { margin: 1em; line-height: 1.6; }
    h1 { font-size: 1.3em; text-align: center; margin: 1em 0; }
    p { text-indent: 1.5em; margin: 0 0 0.6em 0; text-align: justify; }
    nav ol { list-style: none; padding-left: 0; }
    nav li { margin: 0.35em 0; }
    img.cover { display: block; margin: 0 auto; max-width: 100%; }
    """

    private static func xhtml(title: String, body: String) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="vi">
        <head>
        <meta charset="utf-8"/>
        <title>\(title)</title>
        <link rel="stylesheet" type="text/css" href="style.css"/>
        </head>
        <body>
        \(body)</body>
        </html>
        """
    }

    private func coverXhtml() -> String {
        let body = "<div><img class=\"cover\" src=\"cover.jpg\" alt=\"\(ExportTextEscaper.xml(request.bookTitle))\"/></div>\n"
        return Self.xhtml(title: ExportTextEscaper.xml(request.bookTitle), body: body)
    }

    private func navXhtml() -> String {
        var list = "<nav epub:type=\"toc\" id=\"toc\">\n<h1>Mục lục</h1>\n<ol>\n"
        for ref in chapterRefs {
            list += "<li><a href=\"\(ref.href)\">\(ref.title)</a></li>\n"
        }
        list += "</ol>\n</nav>\n"
        return Self.xhtml(title: "Mục lục", body: list)
    }

    private func opfXml() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"

        var metadata = """
        <dc:identifier id="bookid">\(identifier)</dc:identifier>
        <dc:title>\(ExportTextEscaper.xml(request.bookTitle))</dc:title>
        <dc:language>vi</dc:language>
        <dc:creator>\(ExportTextEscaper.xml(request.author.isEmpty ? "Không rõ" : request.author))</dc:creator>
        <meta property="dcterms:modified">\(formatter.string(from: Date()))</meta>

        """
        let description = ExportTextEscaper.xml(request.desc)
        if !description.isEmpty {
            metadata += "<dc:description>\(description)</dc:description>\n"
        }
        if hasCover {
            metadata += "<meta name=\"cover\" content=\"cover-image\"/>\n"
        }

        var manifest = """
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="css" href="style.css" media-type="text/css"/>

        """
        var spine = ""
        if hasCover {
            manifest += "<item id=\"cover-image\" href=\"cover.jpg\" media-type=\"image/jpeg\" properties=\"cover-image\"/>\n"
            manifest += "<item id=\"cover\" href=\"cover.xhtml\" media-type=\"application/xhtml+xml\"/>\n"
            spine += "<itemref idref=\"cover\"/>\n"
        }
        spine += "<itemref idref=\"nav\"/>\n"
        for ref in chapterRefs {
            manifest += "<item id=\"\(ref.id)\" href=\"\(ref.href)\" media-type=\"application/xhtml+xml\"/>\n"
            spine += "<itemref idref=\"\(ref.id)\"/>\n"
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        \(metadata)</metadata>
        <manifest>
        \(manifest)</manifest>
        <spine>
        \(spine)</spine>
        </package>
        """
    }
}
