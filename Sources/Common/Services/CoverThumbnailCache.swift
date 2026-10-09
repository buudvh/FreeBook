import Foundation
import UIKit
import ImageIO

/// Cache RAM cho thumbnail ảnh bìa đã giải mã sẵn, dùng chung cho mọi `BookCoverView`.
///
/// - Key = `bookId` + kích thước pixel hiển thị. Ảnh được downsample bằng ImageIO và giải mã
///   ngay trên luồng gọi (`kCGImageSourceShouldCacheImmediately`), nên lần vẽ đầu trên main
///   không còn phải giải mã JPEG full-res.
/// - `NSCache` tự thread-safe và tự nhả khi thiếu bộ nhớ; chi phí = số byte pixel.
/// - Sổ sách key theo `bookId` + generation đi qua `lock`: `invalidate` xoá được mọi kích thước
///   của một sách, và lượt đọc đĩa bắt đầu trước khi file bìa đổi sẽ không chèn ảnh cũ vào lại.
final class CoverThumbnailCache: @unchecked Sendable {
    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var keysByBookId: [String: Set<String>] = [:]
    private var generations: [String: UInt64] = [:]

    init(totalCostLimit: Int = 48 * 1024 * 1024) {
        cache.totalCostLimit = totalCostLimit
    }

    /// Chỉ tra RAM, không đụng đĩa.
    func image(for bookId: String, pixelSize: CGSize) -> UIImage? {
        cache.object(forKey: Self.key(bookId, pixelSize) as NSString)
    }

    /// Chụp generation TRƯỚC khi đọc đĩa rồi truyền lại cho `insert`.
    func currentGeneration(for bookId: String) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generations[bookId] ?? 0
    }

    /// Bỏ qua nếu bìa đã bị `invalidate` kể từ lúc chụp `generation`.
    func insert(_ image: UIImage, for bookId: String, pixelSize: CGSize, generation: UInt64) {
        let key = Self.key(bookId, pixelSize)
        lock.lock()
        defer { lock.unlock() }
        guard (generations[bookId] ?? 0) == generation else { return }
        cache.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
        keysByBookId[bookId, default: []].insert(key)
    }

    /// Xoá mọi kích thước thumbnail của một sách.
    func invalidate(bookId: String) {
        lock.lock()
        defer { lock.unlock() }
        generations[bookId, default: 0] &+= 1
        for key in keysByBookId.removeValue(forKey: bookId) ?? [] {
            cache.removeObject(forKey: key as NSString)
        }
    }

    // MARK: - Tạo thumbnail

    /// Đọc file bìa và tạo thumbnail đủ phủ kín `pixelSize` theo kiểu aspect-fill
    /// (không phóng to quá ảnh gốc). Có I/O và giải mã: chỉ gọi ở luồng nền.
    static func makeThumbnail(contentsOf url: URL, pixelSize: CGSize, scale: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if let maxPixel = maxPixelSize(for: source, filling: pixelSize) {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixel
        }
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: max(scale, 1), orientation: .up)
    }

    /// Cạnh dài tối đa để ảnh sau downsample vẫn phủ kín khung `target` khi aspect-fill.
    /// `nil` khi không đọc được kích thước gốc (ImageIO sẽ giữ nguyên độ phân giải).
    private static func maxPixelSize(for source: CGImageSource, filling target: CGSize) -> Int? {
        guard target.width > 0, target.height > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              rawWidth > 0, rawHeight > 0 else {
            return nil
        }
        // EXIF orientation 5...8 xoay 90°: kích thước hiển thị bị đảo chiều.
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let width = orientation >= 5 ? rawHeight : rawWidth
        let height = orientation >= 5 ? rawWidth : rawHeight

        let longestSide = max(width, height)
        let fillScale = max(Double(target.width) / width, Double(target.height) / height)
        guard fillScale < 1 else { return Int(longestSide.rounded(.up)) }
        return max(1, Int((longestSide * fillScale).rounded(.up)))
    }

    private static func key(_ bookId: String, _ pixelSize: CGSize) -> String {
        "\(bookId)|\(Int(pixelSize.width.rounded()))x\(Int(pixelSize.height.rounded()))"
    }

    private static func cost(of image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        return max(1, Int(pixelWidth * pixelHeight * 4))
    }
}
