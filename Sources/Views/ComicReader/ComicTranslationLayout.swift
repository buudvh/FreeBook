import CoreGraphics

/// Đo đạc chung của lớp dịch ảnh truyện tranh (1.3.834) — một nguồn cho bản SwiftUI trên trang
/// (`ComicTranslationOverlay`) và bản UIKit trong trình xem phóng to (`ComicZoomTranslationLayer`), để hai nơi đặt khối
/// đúng một chỗ, cùng cỡ chữ, cùng màu.
///
/// Mọi số đo tính trên **cỡ ảnh đang vẽ ở 1×** (điểm). Trình xem phóng to đặt khối ở 1× rồi để `UIScrollView` phóng cả ảnh
/// lẫn khối.
enum ComicTranslationLayout {
    /// Bản dịch tiếng Việt dài hơn chữ Hán: cho khung nở ngang thêm chừng này (vẫn trong biên ảnh).
    static let widthGrowth: CGFloat = 0.15
    static let fontScale: CGFloat = 0.85
    static let minimumFontSize: CGFloat = 9
    static let maximumFontSize: CGFloat = 22
    /// Chữ dài hơn khung thì thu nhỏ tới tỉ lệ này của cỡ khởi điểm.
    static let minimumScaleFactor: CGFloat = 0.4
    static let cornerRadius: CGFloat = 5
    static let horizontalPadding: CGFloat = 3
    static let verticalPadding: CGFloat = 2
    /// Nền khối: trắng (nền ảnh sáng) / đen (nền ảnh tối), chữ màu ngược lại.
    static let lightBackgroundOpacity: CGFloat = 0.95
    static let darkBackgroundOpacity: CGFloat = 0.85

    /// Khung vẽ của khối theo điểm: khung chữ gốc nở ngang `widthGrowth` (+ 6 pt) và cao thêm 4 pt quanh tâm, kẹp trong ảnh.
    static func displayFrame(for block: ComicTextBlock, in size: CGSize) -> CGRect {
        let base = CGRect(
            x: CGFloat(block.x) * size.width,
            y: CGFloat(block.y) * size.height,
            width: CGFloat(block.width) * size.width,
            height: CGFloat(block.height) * size.height
        )
        let width = min(size.width, base.width * (1 + widthGrowth) + 6)
        let height = min(size.height, base.height + 4)
        let minX = min(max(0, base.midX - width / 2), max(0, size.width - width))
        let minY = min(max(0, base.midY - height / 2), max(0, size.height - height))
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    /// Cỡ chữ khởi điểm theo chiều cao dòng của chữ gốc trên ảnh đang vẽ; chữ dài hơn khung thì thu nhỏ tới
    /// `minimumScaleFactor` lần.
    static func fontSize(for block: ComicTextBlock, imageHeight: CGFloat) -> CGFloat {
        let raw = CGFloat(block.lineHeight) * imageHeight * fontScale
        return min(max(raw, minimumFontSize), maximumFontSize)
    }
}
