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
        }
    }
}
