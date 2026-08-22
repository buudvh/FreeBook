import SwiftUI

/// Nội dung của widget trình duyệt thu nhỏ (viên pill "N tab").
///
/// View này **chỉ vẽ**: vị trí, kéo/thả, snap cạnh và tap-để-mở do
/// `BrowserFloatingWidgetContainerViewController` (UIKit) xử lý, giống TTS widget.
/// Nhịp nháy chỉ đổi `opacity` nên không ảnh hưởng alpha/hit-testing của view container.
struct VisibleBrowserReopenButton: View {
    let tabCount: Int

    @ObservedObject private var pulseMonitor = VisibleBrowserPulseMonitor.shared
    @State private var isDimmed = false

    var body: some View {
        pillContent
            .opacity(isDimmed ? 0.45 : 1.0)
            .animation(
                pulseMonitor.isPulsing
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .easeInOut(duration: 0.2),
                value: isDimmed
            )
            .onAppear { isDimmed = pulseMonitor.isPulsing }
            .onChange(of: pulseMonitor.isPulsing) { _, newValue in
                isDimmed = newValue
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mở lại trình duyệt (\(tabCount) tab)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                VisibleBrowserTabManager.shared.reopenContainer()
            }
    }

    private var pillContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 13, weight: .semibold))
            Text("\(tabCount) tab")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
        .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 10, x: 0, y: 4)
        .contentShape(Capsule())
    }
}
