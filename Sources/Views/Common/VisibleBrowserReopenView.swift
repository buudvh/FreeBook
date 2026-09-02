import SwiftUI

/// Nội dung của widget trình duyệt thu nhỏ (viên pill "N tab").
///
/// View này **chỉ vẽ**: vị trí, kéo/thả, snap cạnh và tap-để-mở do
/// `BrowserFloatingWidgetContainerViewController` (UIKit) xử lý, giống TTS widget.
/// Nhịp nháy khi trình duyệt mở lâu chỉ đổi **màu** (đỏ sẫm ↔ đỏ tươi, alpha luôn 1),
/// không đổi opacity của pill nên alpha/hit-testing của view container giữ nguyên.
struct VisibleBrowserReopenButton: View {
    let tabCount: Int

    @ObservedObject private var pulseMonitor = VisibleBrowserPulseMonitor.shared

    /// Pha của nhịp nháy: `true` = đỏ tươi, `false` = đỏ sẫm. Chỉ có nghĩa khi
    /// `pulseMonitor.isPulsing == true`.
    @State private var isPulseBright = false

    var body: some View {
        pillContent
            .animation(
                pulseMonitor.isPulsing
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .easeInOut(duration: 0.2),
                value: pulseLevel
            )
            .onAppear { isPulseBright = pulseMonitor.isPulsing }
            .onChange(of: pulseMonitor.isPulsing) { _, newValue in
                isPulseBright = newValue
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mở lại trình duyệt (\(tabCount) tab)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                VisibleBrowserTabManager.shared.reopenContainer()
            }
    }

    /// 0 = đỏ sẫm nhất, 1 = đỏ tươi nhất. Dùng làm giá trị cho `animation(value:)`
    /// và để nội suy màu — **không** bao giờ dùng làm opacity.
    private var pulseLevel: Double {
        guard pulseMonitor.isPulsing else { return 0 }
        return isPulseBright ? 1.0 : 0.4
    }

    /// Màu đỏ đặc (alpha = 1) nội suy theo `pulseLevel`.
    private var pulseColor: Color {
        Color(
            red: 0.42 + 0.48 * pulseLevel,
            green: 0.04 + 0.13 * pulseLevel,
            blue: 0.04 + 0.13 * pulseLevel
        )
    }

    private var pillContent: some View {
        HStack(spacing: 6) {
            // Icon Safari thay cho `globe`: nó là thứ người dùng nhận ra ngay là "trình duyệt".
            Image(systemName: "safari")
                .font(.system(size: 14, weight: .semibold))
            Text("\(tabCount) tab")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(pulseMonitor.isPulsing ? Color.white : Color.primary)
        .padding(.horizontal, 11)
        // Bằng 2/3 chiều cao widget nghe truyện (56) — xem `BrowserFloatingWidgetContainerViewController`.
        .frame(height: 38)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    if pulseMonitor.isPulsing {
                        Capsule(style: .continuous).fill(pulseColor)
                    }
                }
        )
        .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 10, x: 0, y: 4)
        .contentShape(Capsule())
    }
}
