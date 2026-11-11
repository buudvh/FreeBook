import SwiftUI

/// **Nửa viên thuốc dính mép màn** (anh Bửu duyệt mockup 2026-11-11): cạnh phẳng áp sát mép trái / phải, đầu bo tròn
/// (bán kính = nửa chiều cao) quay vào trong màn. Một khuôn cho đĩa nghe (`MediaDiscContainerViewController`), nút hub và
/// nút trình duyệt thu nhỏ — nền là kính `FloatingGlassBackground(shape:)` như nút "+".
///
/// - `edge == nil` ⇒ viên thuốc / hình tròn đủ (lúc đang kéo theo tay).
/// - Cạnh phẳng vẽ **tràn 1 pt ra ngoài khung** về phía mép: viền mảnh của kính rơi ra ngoài màn, không thành vạch sáng dọc
///   mép (khung view vẫn đúng cỡ, cửa sổ cắt phần tràn).
/// - Nội dung (bìa / icon) đặt **đồng tâm đầu bo**: cách đầu bo đúng `cornerRadius(for:)` ⇒ dùng `contentInset(for:content:)`.
struct EdgePillShape: Shape {
    /// Đĩa nghe: rộng 68 = lề 16 + nút "+" 52 ⇒ bìa 32 pt thẳng cột với icon "+" (cách mép 42 pt).
    static let largeSize = CGSize(width: 68, height: 52)
    /// Nút hub và nút trình duyệt: cao 36 như nút tròn cũ, rộng 38 (icon cách mép 20 pt).
    static let smallSize = CGSize(width: 38, height: 36)

    var edge: EdgeDirection?

    /// Bán kính đầu bo của khung `size`.
    static func cornerRadius(for size: CGSize) -> CGFloat {
        min(size.width, size.height) / 2
    }

    /// Lề từ đầu bo tới nội dung cỡ `content` để nội dung đồng tâm đầu bo.
    static func contentInset(for size: CGSize, content: CGFloat) -> CGFloat {
        max(0, cornerRadius(for: size) - content / 2)
    }

    /// Căn nội dung theo mép đang dính: mép phải ⇒ đầu bo ở bên trái (leading); mép trái ⇒ bên phải; đang kéo ⇒ giữa.
    static func contentAlignment(for edge: EdgeDirection?) -> Alignment {
        switch edge {
        case .right: return .leading
        case .left: return .trailing
        case nil: return .center
        }
    }

    func path(in rect: CGRect) -> Path {
        let radius = Self.cornerRadius(for: rect.size)
        var drawRect = rect
        let radii: RectangleCornerRadii
        switch edge {
        case .right:
            drawRect.size.width += 1
            radii = RectangleCornerRadii(topLeading: radius, bottomLeading: radius, bottomTrailing: 0, topTrailing: 0)
        case .left:
            drawRect.origin.x -= 1
            drawRect.size.width += 1
            radii = RectangleCornerRadii(topLeading: 0, bottomLeading: 0, bottomTrailing: radius, topTrailing: radius)
        case nil:
            radii = RectangleCornerRadii(
                topLeading: radius,
                bottomLeading: radius,
                bottomTrailing: radius,
                topTrailing: radius
            )
        }
        return UnevenRoundedRectangle(cornerRadii: radii, style: .circular).path(in: drawRect)
    }
}
