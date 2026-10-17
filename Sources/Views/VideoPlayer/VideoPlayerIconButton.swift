import SwiftUI

/// Nút chỉ có biểu tượng của trình phát: SF Symbol 17pt semibold, hitbox 36 × 38pt (chuẩn header của app).
/// Dùng chung cho thanh trên / thanh dưới; nhãn trợ năng bắt buộc vì nút không có chữ.
struct VideoPlayerIconButton: View {
    let systemName: String
    /// Nhãn trợ năng.
    let label: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VideoPlayerIconLabel(systemName: systemName, isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
