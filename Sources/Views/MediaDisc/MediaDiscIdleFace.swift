import SwiftUI

/// Đĩa **nghỉ** ở ô giữa thanh tab khi không nghe gì (1.3.821, anh Bửu chọn kiểu "đĩa xám mờ"): đĩa than xám đứng yên — nền
/// + vài vòng rãnh + nhãn giữa theo các tông `systemGray` (như icon tab chưa chọn, tự đổi theo nền sáng / tối), viền mảnh như
/// đĩa đang nghe. Chỉ là hình: không nhận chạm, VoiceOver bỏ qua. Bắt đầu nghe ⇒ `MediaDiscTabBarSlot` đổi sang
/// `MediaDiscFaceButton(.tabBar)` (bìa xoay).
struct MediaDiscIdleFace: View {
    let size: CGFloat

    /// Đường kính các vòng rãnh, theo tỉ lệ đĩa.
    private static let grooveRatios: [CGFloat] = [0.86, 0.72, 0.58]
    private static let labelRatio: CGFloat = 0.36
    private static let holeRatio: CGFloat = 0.09

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .systemGray4))
            ForEach(Self.grooveRatios, id: \.self) { ratio in
                Circle()
                    .stroke(Color(uiColor: .systemGray3), lineWidth: 0.6)
                    .frame(width: size * ratio, height: size * ratio)
            }
            Circle()
                .fill(Color(uiColor: .systemGray2))
                .frame(width: size * Self.labelRatio, height: size * Self.labelRatio)
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: size * Self.holeRatio, height: size * Self.holeRatio)
            Circle()
                .stroke(Color.primary.opacity(0.18), lineWidth: 0.75)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
