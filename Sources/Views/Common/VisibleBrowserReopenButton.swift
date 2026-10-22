import SwiftUI

/// Nút nổi của widget trình duyệt thu nhỏ: **nút tròn 36px**, cùng khuôn nút hub (dựng lại ở 1.3.533).
///
/// - Bung (`.revealed`): icon `safari` 17pt + badge **số tab** (`> 99` ⇒ `99+`).
/// - Dán mép (`.peeking`): badge thu thành **chấm đỏ 9px**, và badge **lật phía** theo mép — ở trạng thái
///   thu gọn tâm nút nằm đúng trên mép nên badge đặt cố định sẽ ra ngoài màn.
///
/// ## Nhịp nháy
/// `VisibleBrowserPulseMonitor` báo tab đã thu nhỏ quá 10 giây ⇒ nút nháy đỏ. Nhịp nháy đổi bằng **màu**
/// (nội suy đỏ sẫm ↔ đỏ tươi, alpha luôn 1), **không** bằng opacity của view này.
///
/// ## Độ trong suốt
/// Độ mờ khi nghỉ (0,7) do container đặt trên **hosting view** của nút, không nằm ở đây và không đặt trên
/// `widgetContainerView` hay cửa sổ: `BrowserFloatingWidgetUIWindow.hitTest` có guard `alpha > 0.01` trên
/// `widgetContainerView`.
///
/// View này **chỉ vẽ**: vị trí, kéo/thả, snap cạnh và chạm-để-mở do
/// `BrowserFloatingWidgetContainerViewController` (UIKit) xử lý. `onActivate` chỉ dùng cho VoiceOver.
struct VisibleBrowserReopenButton: View {
    /// Cỡ nút, dùng chung cho cả hai trạng thái.
    static let size: CGFloat = 36

    let tabCount: Int
    let mode: WidgetMode
    /// Mép nút đang dán — quyết định phía đặt badge.
    let edge: EdgeDirection
    /// Mở lại trình duyệt — cùng đường với chạm.
    let onActivate: () -> Void

    @ObservedObject private var pulseMonitor = VisibleBrowserPulseMonitor.shared

    /// Pha của nhịp nháy: `true` = đỏ tươi, `false` = đỏ sẫm. Chỉ có nghĩa khi `pulseMonitor.isPulsing == true`.
    @State private var isPulseBright = false

    var body: some View {
        ZStack(alignment: badgeAlignment) {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: Self.size, height: Self.size)
                .overlay {
                    if pulseMonitor.isPulsing {
                        Circle().fill(pulseColor)
                    }
                }
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 3)

            // Icon Safari thay cho `globe`: nó là thứ người dùng nhận ra ngay là "trình duyệt".
            Image(systemName: "safari")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(pulseMonitor.isPulsing ? Color.white : Color.primary)
                .frame(width: Self.size, height: Self.size)

            if tabCount > 0 {
                badge
            }
        }
        .frame(width: Self.size, height: Self.size)
        .animation(
            pulseMonitor.isPulsing
                ? .easeInOut(duration: FloatingHubPulseView.pulseHalfPeriod).repeatForever(autoreverses: true)
                : .easeInOut(duration: 0.2),
            value: pulseLevel
        )
        .onAppear { isPulseBright = pulseMonitor.isPulsing }
        .onChange(of: pulseMonitor.isPulsing) { _, newValue in
            isPulseBright = newValue
        }
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mở lại trình duyệt (\(tabCount) tab)")
        .accessibilityAddTraits(.isButton)
        // Kích hoạt bằng VoiceOver không chắc đi qua `UITapGestureRecognizer` của container.
        .accessibilityAction {
            onActivate()
        }
    }

    /// Bung: badge **số tab** ở góc trên-phải. Thu gọn: **chấm đỏ**, lật về phía còn nhìn thấy.
    @ViewBuilder
    private var badge: some View {
        if mode == .revealed {
            Text(tabCount > 99 ? "99+" : "\(tabCount)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.red, in: Capsule())
                .offset(badgeOffset)
        } else {
            Circle()
                .fill(Color.red)
                .frame(width: 9, height: 9)
                .offset(badgeOffset)
        }
    }

    private var badgeAlignment: Alignment {
        guard mode == .peeking, edge == .right else { return .topTrailing }
        return .topLeading
    }

    private var badgeOffset: CGSize {
        let out: CGFloat = mode == .peeking ? 3 : 6
        // `.topLeading` + offset âm = đẩy ra ngoài về bên trái (phía còn thấy khi dán mép phải).
        let horizontal = (mode == .peeking && edge == .right) ? -out : out
        return CGSize(width: horizontal, height: -out)
    }

    /// 0 = đỏ sẫm nhất, 1 = đỏ tươi nhất. Dùng làm giá trị cho `animation(value:)` và để nội suy màu —
    /// **không** bao giờ dùng làm opacity. Màu, đáy nhịp và nhịp đọc chung hằng với nút hub (`FloatingHubPulseView`).
    private var pulseLevel: Double {
        guard pulseMonitor.isPulsing else { return 0 }
        return isPulseBright ? 1.0 : FloatingHubPulseView.pulseDimLevel
    }

    /// Màu đỏ đặc (alpha = 1) nội suy theo `pulseLevel`.
    private var pulseColor: Color {
        let rgb = FloatingHubPulseView.pulseRGB(level: pulseLevel)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
