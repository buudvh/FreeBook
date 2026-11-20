import SwiftUI

/// Nút chỉ có biểu tượng của trình phát: SF Symbol 17pt semibold, hitbox 36 × 38pt (chuẩn header của app).
/// Dùng chung cho thanh trên / thanh dưới; nhãn trợ năng bắt buộc vì nút không có chữ.
struct VideoPlayerIconButton: View {
    let systemName: String
    /// Nhãn trợ năng.
    let label: String
    var isActive = false
    /// Rộng khung; cụm nút đứng sát nhau dùng `HeaderButtonMetrics.pairIconWidth`.
    var width: CGFloat = 36
    /// Canh icon trong khung (`VideoPlayerIconLabel.alignment`): nút ngoài cùng của thanh trên canh vào lề.
    var alignment: Alignment = .center
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VideoPlayerIconLabel(systemName: systemName, isActive: isActive, width: width, alignment: alignment)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
