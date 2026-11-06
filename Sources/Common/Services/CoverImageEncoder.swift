import Foundation
import ImageIO
import UIKit

/// Mã hoá ảnh bìa trước khi ghi `covers/<sha256(bookId)>.jpg` (1.3.762): cạnh dài ≤ `maxPixelSize` **pixel thật**, JPEG.
///
/// - Dựng bằng ImageIO (`CGImageSourceCreateThumbnailAtIndex`): giải mã thẳng ra bản thu nhỏ, không bao giờ giữ ảnh
///   nguyên cỡ trong RAM, và xoay theo EXIF sẵn. Không phóng to ảnh nhỏ hơn giới hạn.
/// - Không dùng `UIGraphicsImageRenderer`: format mặc định của nó nhân scale màn hình, nên "1024" cũ của `saveCover`
///   thực ra ghi tới 3072 px trên máy 3x.
/// - 1024 px đủ cho chỗ hiện bìa lớn nhất (bìa dọc 150×210 pt ở trang Chi tiết ≈ 450×630 px trên máy 3x).
enum CoverImageEncoder {
    static let maxPixelSize = 1024
    static let jpegQuality: CGFloat = 0.8

    /// Byte ảnh bất kỳ (JPEG, PNG, WebP…) → JPEG đã thu nhỏ + ảnh tương ứng. `nil` khi không phải ảnh.
    static func encode(_ data: Data, maxPixelSize: Int = maxPixelSize, quality: CGFloat = jpegQuality) -> (jpeg: Data, image: UIImage)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        return encode(source: source, maxPixelSize: maxPixelSize, quality: quality)
    }

    /// Như `encode(_:)` nhưng đọc từ file (thu nhỏ bìa cũ quá cỡ). Có I/O + giải mã: chỉ gọi ở luồng nền.
    static func encode(contentsOf url: URL, maxPixelSize: Int = maxPixelSize, quality: CGFloat = jpegQuality) -> (jpeg: Data, image: UIImage)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        return encode(source: source, maxPixelSize: maxPixelSize, quality: quality)
    }

    /// Cạnh dài (pixel) đọc từ header, không giải mã ảnh. `nil` khi không đọc được.
    static func longestPixelSide(of url: URL) -> Int? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            return nil
        }
        return max(width, height)
    }

    private static let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary

    private static func encode(source: CGImageSource, maxPixelSize: Int, quality: CGFloat) -> (jpeg: Data, image: UIImage)? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        guard let jpeg = image.jpegData(compressionQuality: quality) else { return nil }
        return (jpeg, image)
    }
}
