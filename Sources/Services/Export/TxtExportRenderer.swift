import Foundation

/// Xuất TXT — giữ **đúng từng byte** bố cục của bản xuất cũ (`DownloadManager.formatChapter` +
/// `TxtExportFileWriter`): mỗi chương là `"<tiêu đề>\n\n"` rồi từng đoạn thụt vào 4 khoảng trắng và nối
/// bằng `"\n\n"`; giữa hai chương thêm `"\n\n"`.
///
/// Khác duy nhất so với 1.3.252: tên file mang thêm mốc thời gian (`ExportFileNaming`) nên lần xuất sau
/// **không ghi đè im lặng** lần trước.
final class TxtExportRenderer: ExportRenderer {
    private let staging: ExportStagingFile
    private(set) var writtenChapterCount = 0

    init(request: BookExportRequest) throws {
        let target = try ExportFileNaming.targetURL(bookTitle: request.bookTitle, format: .txt)
        staging = try ExportStagingFile(targetURL: target)
    }

    var hasContent: Bool { staging.didWriteNonWhitespace }

    func append(_ chapter: ExportChapterPayload) throws {
        let body = ExportParagraphSplitter.paragraphs(from: chapter.content)
            .map { "    " + $0 }
            .joined(separator: "\n\n")
        // Dấu phân tách đi trước chương, đúng thứ tự của bộ đệm chuỗi cũ.
        if writtenChapterCount > 0 {
            try staging.write("\n\n")
        }
        try staging.write("\(chapter.title)\n\n\(body)")
        writtenChapterCount += 1
    }

    func finish() throws -> ExportArtifact {
        guard hasContent else {
            staging.discard()
            throw ExportRenderError.emptyExport
        }
        let url = try staging.commit()
        return ExportArtifact(fileURL: url, format: .txt, chapterCount: writtenChapterCount)
    }

    func discard() {
        staging.discard()
    }
}
