import SwiftUI

/// Nút capsule cao 38pt chia đều hàng (sheet Dịch QT): icon + chữ 13pt nửa đậm, nền mờ của màu chữ — không dùng màu
/// nhấn (màu nhấn của app là trắng). Bị `disabled` thì mờ đi.
struct BrowserCapsuleButton<Icon: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon()
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(Color.primary.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}
