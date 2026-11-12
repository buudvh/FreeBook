import SwiftUI

/// **Nửa viên thuốc dính mép màn** (anh Bửu duyệt mockup 2026-11-11): cạnh phẳng áp sát mép trái / phải, đầu bo tròn
/// (bán kính = nửa chiều cao) quay vào trong màn. Một khuôn cho đĩa nghe (`MediaDiscContainerViewController`), nút hub và
/// nút trình duyệt thu nhỏ — nền là kính `FloatingGlassBackground(shape:)` như nút "+".
///
/// - Chiều rộng (độ nhô) do người dùng chỉnh theo từng viên (`EdgePillSettings`), thấp nhất = nửa chiều cao ⇒ **bán
///   nguyệt**. Đường viền vẽ tay bằng cung tiếp tuyến (không dùng `UnevenRoundedRectangle`: bán kính lớn hơn nửa cạnh ngắn
///   có thể bị kẹp ⇒ bán nguyệt thành chữ nhật bo góc).
/// - `edge == nil` ⇒ viên thuốc / hình tròn đủ (lúc đang kéo theo tay).
/// - Cạnh phẳng vẽ **tràn 1 pt ra ngoài khung** về phía mép: viền mảnh của kính rơi ra ngoài màn, không thành vạch sáng dọc
///   mép (khung view vẫn đúng cỡ, cửa sổ cắt phần tràn).
/// - Nội dung (bìa / icon) đặt **đồng tâm đầu bo**: cách đầu bo đúng `cornerRadius(for:)` ⇒ dùng `contentInset(height:content:)`
///   và gắn bằng `overlay(alignment:)` (nội dung rộng hơn viên thì tràn ra phía mép, không đẩy khung kính).
struct EdgePillShape: Shape {
    var edge: EdgeDirection?

    /// Bán kính đầu bo của khung `size`: nửa chiều cao, không quá chiều rộng (bán nguyệt).
    static func cornerRadius(for size: CGSize) -> CGFloat {
        max(0, min(size.height / 2, size.width))
    }

    /// Lề từ đầu bo tới nội dung cỡ `content` để nội dung đồng tâm đầu bo — tính theo **chiều cao** của viên (`height`).
    static func contentInset(height: CGFloat, content: CGFloat) -> CGFloat {
        height / 2 - content / 2
    }

    /// Căn nội dung theo mép đang dính: mép phải ⇒ đầu bo ở bên trái (leading); mép trái ⇒ bên phải; đang kéo ⇒ giữa.
    static func contentAlignment(for edge: EdgeDirection?) -> Alignment {
        switch edge {
        case .right: return .leading
        case .left: return .trailing
        case nil: return .center
        }
    }

    /// Lề đặt nội dung theo mép (dùng với `contentAlignment`): `nil` ⇒ không lề (giữa hình tròn).
    static func contentPadding(for edge: EdgeDirection?) -> Edge.Set {
        edge == .left ? .trailing : .leading
    }

    func path(in rect: CGRect) -> Path {
        let radius = Self.cornerRadius(for: rect.size)
        guard let edge else {
            return RoundedRectangle(cornerRadius: min(rect.width, rect.height) / 2, style: .circular).path(in: rect)
        }
        var path = Path()
        switch edge {
        case .right:
            // Đầu bo bên trái, cạnh phẳng bên phải (tràn 1 pt).
            let flatX = rect.maxX + 1
            path.move(to: CGPoint(x: flatX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                tangent2End: CGPoint(x: rect.minX, y: rect.maxY),
                radius: radius
            )
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                tangent2End: CGPoint(x: flatX, y: rect.maxY),
                radius: radius
            )
            path.addLine(to: CGPoint(x: flatX, y: rect.maxY))
        case .left:
            // Đầu bo bên phải, cạnh phẳng bên trái (tràn 1 pt).
            let flatX = rect.minX - 1
            path.move(to: CGPoint(x: flatX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                tangent2End: CGPoint(x: rect.maxX, y: rect.maxY),
                radius: radius
            )
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                tangent2End: CGPoint(x: flatX, y: rect.maxY),
                radius: radius
            )
            path.addLine(to: CGPoint(x: flatX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
