import SwiftUI

/// Khung cắt bo góc của khung phim lúc co (`VideoMinimizeDragContainer`). Chưa co (`isClipping == false`) thì trả một
/// hình chữ nhật rộng hơn hẳn khung — không cắt gì, để toàn màn / nằm ngang vẫn tràn qua vùng an toàn như trước. Giữ
/// cùng một modifier ở mọi trạng thái (không bật/tắt modifier) để SwiftUI không dựng lại khung phim.
struct VideoMinimizeClipShape: Shape {
    var cornerRadius: CGFloat
    var isClipping: Bool

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard isClipping else {
            return Path(rect.insetBy(dx: -4_000, dy: -4_000))
        }
        return Path(roundedRect: rect, cornerRadius: max(0, cornerRadius), style: .continuous)
    }
}
