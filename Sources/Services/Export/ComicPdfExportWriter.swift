import Foundation
import ImageIO
import UIKit

/// Xuất truyện tranh ra **PDF**: mỗi ảnh một trang đúng tỉ lệ ảnh, theo thứ tự chương (`UIGraphicsPDFRenderer`, ghi
/// thẳng xuống `.part` rồi mới đổi tên — huỷ/lỗi thì bỏ `.part`, không để lại file dở trong `Documents/Exports/`).
///
/// - JPEG không xoay EXIF ⇒ nhúng nguyên dữ liệu JPEG (`CGImage(jpegDataProviderSource:)`): không giải mã cả ảnh, không
///   nén lại, PDF xấp xỉ tổng dung lượng ảnh. Định dạng khác giải mã qua ImageIO (đã xoay EXIF) rồi vẽ trên nền trắng.
/// - Trang PDF tối đa 14.400 điểm mỗi cạnh: ảnh dài hơn (webtoon) thì thu nhỏ cả trang.
/// - Khối vẽ của renderer là đồng bộ ⇒ kiểm `Task.isCancelled` từng ảnh, mỗi ảnh một `autoreleasepool`.
enum ComicPdfExportWriter {
    private static let maxPageSide: CGFloat = 14_400

    static func write(
        chapters: [ComicExportChapter],
        title: String,
        author: String,
        to target: URL,
        onChapterDone: (ComicExportChapter) -> Void
    ) throws -> URL {
        let fileManager = FileManager.default
        let partURL = ExportFileNaming.stagingURL(for: target)
        if fileManager.fileExists(atPath: partURL.path) {
            try fileManager.removeItem(at: partURL)
        }
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextAuthor as String: author,
            kCGPDFContextCreator as String: "FreeBook"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792), format: format)
        var pageCount = 0
        var wasCancelled = false
        do {
            try renderer.writePDF(to: partURL) { context in
                for chapter in chapters {
                    for page in chapter.pages {
                        if Task.isCancelled {
                            wasCancelled = true
                            return
                        }
                        autoreleasepool {
                            if drawPage(at: page, in: context) {
                                pageCount += 1
                            }
                        }
                    }
                    onChapterDone(chapter)
                }
            }
        } catch {
            try? fileManager.removeItem(at: partURL)
            throw error
        }
        guard !wasCancelled else {
            try? fileManager.removeItem(at: partURL)
            throw CancellationError()
        }
        guard pageCount > 0 else {
            try? fileManager.removeItem(at: partURL)
            throw ExportRenderError.emptyExport
        }
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        try fileManager.moveItem(at: partURL, to: target)
        return target
    }

    /// Một ảnh thành một trang. `false` khi ảnh không đọc được (bỏ qua, ghi log).
    private static func drawPage(at url: URL, in context: UIGraphicsPDFRendererContext) -> Bool {
        guard let image = pageImage(at: url) else {
            AppLogger.shared.log("⚠️ [ComicExport] Bỏ qua ảnh không đọc được khi xuất PDF: \(url.lastPathComponent)")
            return false
        }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1, maxPageSide / max(width, height))
        let bounds = CGRect(x: 0, y: 0, width: width * scale, height: height * scale)
        context.beginPage(withBounds: bounds, pageInfo: [:])
        context.cgContext.setFillColor(UIColor.white.cgColor)
        context.cgContext.fill(bounds)
        UIImage(cgImage: image).draw(in: bounds)
        return true
    }

    private static func pageImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if orientation == 1,
           (CGImageSourceGetType(source) as String?) == "public.jpeg",
           let provider = CGDataProvider(url: url as CFURL),
           let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
            return jpeg
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPageSide),
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
