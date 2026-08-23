import Foundation

/// Xuất FB2 (FictionBook 2.0) — một file XML duy nhất, ghi dần.
///
/// FB2 xếp `<description>` ở đầu và `<binary>` (ảnh) ở **cuối** tài liệu, còn mục lục do máy đọc tự dựng
/// từ `<section><title>`. Nhờ bố cục đó renderer ghi được tuần tự: metadata lúc `init`, mỗi chương một
/// `<section>` lúc `append`, ảnh bìa base64 lúc `finish` — đỉnh RAM chỉ bằng một chương (cộng ảnh bìa).
final class Fb2ExportRenderer: ExportRenderer {
    private let staging: ExportStagingFile
    private let request: BookExportRequest
    private(set) var writtenChapterCount = 0

    init(request: BookExportRequest) throws {
        self.request = request
        let target = try ExportFileNaming.targetURL(bookTitle: request.bookTitle, format: .fb2)
        staging = try ExportStagingFile(targetURL: target)
        try staging.write(Self.header(for: request))
    }

    /// Header chỉ là metadata nên không tính là "có nội dung" — phải có chương thật.
    var hasContent: Bool { writtenChapterCount > 0 }

    func append(_ chapter: ExportChapterPayload) throws {
        var section = "<section>\n<title><p>\(ExportTextEscaper.xml(chapter.title))</p></title>\n"
        for paragraph in ExportParagraphSplitter.paragraphs(from: chapter.content) {
            section += "<p>\(ExportTextEscaper.xml(paragraph))</p>\n"
        }
        section += "</section>\n"
        try staging.write(section)
        writtenChapterCount += 1
    }

    func finish() throws -> ExportArtifact {
        guard hasContent else {
            staging.discard()
            throw ExportRenderError.emptyExport
        }
        try staging.write("</body>\n")
        if let cover = request.coverJpegData, !cover.isEmpty {
            try staging.write("<binary id=\"cover.jpg\" content-type=\"image/jpeg\">\n")
            try staging.write(cover.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed]))
            try staging.write("\n</binary>\n")
        }
        try staging.write("</FictionBook>\n")
        let url = try staging.commit()
        return ExportArtifact(fileURL: url, format: .fb2, chapterCount: writtenChapterCount)
    }

    func discard() {
        staging.discard()
    }

    private static func header(for request: BookExportRequest) -> String {
        let title = ExportTextEscaper.xml(request.bookTitle)
        let author = ExportTextEscaper.xml(request.author.isEmpty ? "Không rõ" : request.author)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        var header = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
        <description>
        <title-info>
        <genre>prose</genre>
        <author><nickname>\(author)</nickname></author>
        <book-title>\(title)</book-title>

        """
        let annotation = ExportTextEscaper.xml(request.desc)
        if !annotation.isEmpty {
            header += "<annotation><p>\(annotation)</p></annotation>\n"
        }
        if request.coverJpegData?.isEmpty == false {
            header += "<coverpage><image l:href=\"#cover.jpg\"/></coverpage>\n"
        }
        header += """
        <lang>vi</lang>
        </title-info>
        <document-info>
        <author><nickname>FreeBook</nickname></author>
        <program-used>FreeBook</program-used>
        <date value="\(today)">\(today)</date>
        <id>\(ExportTextEscaper.xml(request.bookId))</id>
        <version>1.0</version>
        </document-info>
        </description>
        <body>

        """
        return header
    }
}
