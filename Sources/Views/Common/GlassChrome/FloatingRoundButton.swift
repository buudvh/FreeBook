import SwiftUI

/// Nút tròn nổi 52pt nền kính (`FloatingGlassBackground` ⇒ theo độ trong suốt / độ đục ở Cài đặt › Giao diện), icon
/// trắng 20pt nửa đậm **mờ theo Độ trong suốt** (`floatingIconTransparency`, 2026-11-11) — một khuôn cho nút "+" của màn
/// danh sách, nút Home nổi và nút bật menu xổ (`FloatingActionMenu`).
/// Không tự đệm lề: người gọi đặt `trailingInset` / `bottomInset` (16 / 12) như nút "+" chung. Mọi nút kiểu này là neo
/// của đĩa nghe góc dưới phải (`.mediaDiscAnchor(.button)`, 1.3.808): đĩa đứng ngay trên nút.
struct FloatingRoundButton: View {
    static let size: CGFloat = 52
    static let trailingInset: CGFloat = 16
    static let bottomInset: CGFloat = 12

    let systemImage: String
    let accessibilityLabel: String
    var iconRotation: Angle = .zero
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .floatingIconTransparency()
                .rotationEffect(iconRotation)
                .frame(width: Self.size, height: Self.size)
                .background { FloatingGlassBackground() }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .mediaDiscAnchor(.button)
    }
}
