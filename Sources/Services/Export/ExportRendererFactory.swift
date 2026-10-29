import Foundation

/// Chọn renderer theo định dạng. Đây là chỗ duy nhất biết map `BookExportFormat` → lớp renderer, nên
/// `DownloadManager` không cần biết có bao nhiêu định dạng.
enum ExportRendererFactory {
    static func makeRenderer(for request: BookExportRequest) throws -> ExportRenderer {
        switch request.format {
        case .txt:
            return try TxtExportRenderer(request: request)
        case .epub3:
            return try EpubExportRenderer(request: request)
        case .fb2:
            return try Fb2ExportRenderer(request: request)
        case .mobi:
            return try MobiExportRenderer(request: request)
        case .cbz, .pdf:
            // Định dạng ảnh chỉ dành cho truyện tranh (`DownloadManager+ComicExport`), không bao giờ dựng từ chữ.
            throw ExportRenderError.unsupportedFormat(request.format.displayName)
        }
    }
}
