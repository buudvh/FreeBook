import SwiftUI

/// Nút nổi của widget trình duyệt thu nhỏ — **nửa viên thuốc nhỏ cao 36 dính mép** (anh Bửu duyệt mockup 2026-11-11,
/// thay nút tròn 36px nép mép của 1.3.533): cùng khuôn `EdgePillShape` với đĩa nghe và nút hub. Độ nhô, **Độ trong suốt**
/// và **Độ đục** là cài đặt **riêng của nút trình duyệt** (Giao diện › Viên thuốc nổi, `EdgePillSettings`); icon `safari`
/// 17 pt trắng đồng tâm đầu bo (gắn bằng `overlay`), **mờ đúng số** theo độ trong suốt của nút (không sàn). Đang kéo
/// (`edge == nil`) ⇒ hình tròn.
///
/// - Badge **số tab** (`> 99` ⇒ `99+`) đỏ ở góc trên của icon — luôn rõ, không mờ theo Độ trong suốt; không lật phía
///   (nằm trong nửa viên nên mép nào cũng thấy).
///
/// ## Nhịp nháy
/// `VisibleBrowserPulseMonitor` báo tab đã thu nhỏ quá 10 giây ⇒ nền nửa viên nháy đỏ, **trên** lớp kính (độ đục) của
/// nút. Nhịp nháy đổi bằng **màu** (nội suy đỏ sẫm ↔ đỏ tươi, alpha = `1 − trong suốt` của nút — anh Bửu 2026-11-11,
/// trước đó giữ rõ), **không** bằng opacity của view này.
///
/// View này **chỉ vẽ**: vị trí, kéo/thả, bám mép và chạm-để-mở do `BrowserFloatingWidgetContainerViewController` (UIKit)
/// xử lý. `onActivate` chỉ dùng cho VoiceOver.
struct VisibleBrowserReopenButton: View {
    /// Đường kính lúc đang kéo (= chiều cao).
    static let dragDiameter: CGFloat = EdgePillSettings.Kind.browser.height
    private static let iconBox: CGFloat = 24

    let tabCount: Int
    /// Mép đang dính; `nil` ⇒ đang kéo (hình tròn).
    let edge: EdgeDirection?
    /// Mở lại trình duyệt — cùng đường với chạm.
    let onActivate: () -> Void

    @ObservedObject private var pulseMonitor = VisibleBrowserPulseMonitor.shared
    @AppStorage(EdgePillSettings.Kind.browser.transparencyKey)
    private var transparency = EdgePillSettings.defaultTransparency

    /// Pha của nhịp nháy: `true` = đỏ tươi, `false` = đỏ sẫm. Chỉ có nghĩa khi `pulseMonitor.isPulsing == true`.
    @State private var isPulseBright = false

    var body: some View {
        let shape = EdgePillShape(edge: edge)
        let inset = EdgePillShape.contentInset(height: Self.dragDiameter, content: Self.iconBox)
        return FloatingGlassBackground(shape: AnyShape(shape), pill: .browser)
            .overlay {
                if pulseMonitor.isPulsing {
                    shape.fill(pulseColor)
                }
            }
            .overlay(alignment: EdgePillShape.contentAlignment(for: edge)) {
                // Icon Safari thay cho `globe`: nó là thứ người dùng nhận ra ngay là "trình duyệt".
                Image(systemName: "safari")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .opacity(iconOpacity)
                    .frame(width: Self.iconBox, height: Self.iconBox)
                    .overlay(alignment: .topTrailing) {
                        if tabCount > 0 {
                            badge
                        }
                    }
                    .padding(EdgePillShape.contentPadding(for: edge), edge == nil ? 0 : inset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .contentShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mở lại trình duyệt (\(tabCount) tab)")
            .accessibilityAddTraits(.isButton)
            // Kích hoạt bằng VoiceOver không chắc đi qua `UITapGestureRecognizer` của container.
            .accessibilityAction {
                onActivate()
            }
    }

    /// Số tab, đỏ, ở góc trên-phải của icon (đẩy ra ngoài một chút để không che icon).
    private var badge: some View {
        Text(tabCount > 99 ? "99+" : "\(tabCount)")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.red, in: Capsule())
            .offset(x: 7, y: -5)
    }

    /// Icon (và màu nháy) theo độ trong suốt của nút: 0% ⇒ rõ hẳn, 100% ⇒ trong hẳn (không sàn).
    private var iconOpacity: Double {
        1 - min(1, max(0, transparency))
    }

    /// 0 = đỏ sẫm nhất, 1 = đỏ tươi nhất. Dùng làm giá trị cho `animation(value:)` và để nội suy màu —
    /// **không** bao giờ dùng làm opacity. Màu, đáy nhịp và nhịp đọc chung hằng với nút hub (`FloatingHubPulseView`).
    private var pulseLevel: Double {
        guard pulseMonitor.isPulsing else { return 0 }
        return isPulseBright ? 1.0 : FloatingHubPulseView.pulseDimLevel
    }

    /// Màu đỏ nội suy theo `pulseLevel`, alpha = `1 − trong suốt` của nút (màu, không phải opacity của view).
    private var pulseColor: Color {
        let rgb = FloatingHubPulseView.pulseRGB(level: pulseLevel)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: iconOpacity)
    }
}
