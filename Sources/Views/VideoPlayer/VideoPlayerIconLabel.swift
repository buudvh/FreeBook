import SwiftUI

/// Phần hình của `VideoPlayerIconButton` — dùng lại làm nhãn cho `Menu`.
///
/// Luôn trắng, không theo màu nhấn: trình phát giữ tông trắng trên nền đen dù mở từ đâu. Trạng thái bật/tắt do chính
/// biểu tượng thể hiện (`speaker.slash.fill`, `lock.rotation`…).
struct VideoPlayerIconLabel: View {
    let systemName: String
    /// Giữ để nơi gọi khỏi đổi; không còn đổi màu theo trạng thái.
    var isActive = false
    var width: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: width, height: 38)
            .contentShape(Rectangle())
    }
}
