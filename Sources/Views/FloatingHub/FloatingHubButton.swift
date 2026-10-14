import SwiftUI

/// Nút tròn 36px của hub nổi (1.3.524) — cùng khuôn nút thông báo / trình duyệt cũ: nền `.ultraThinMaterial`,
/// viền trắng 20 %, bóng đen 24 %.
///
/// ## Glyph theo số mục
/// - 1 mục: glyph của chính mục đó (`sparkles` tím / `safari` / `bell.fill` hoặc `bell`).
/// - Từ 2 mục: `square.grid.2x2`.
///
/// ## Chỉ báo
/// - **Chưa đọc** (chỉ khi mục Thông báo có mặt): `.peeking` là chấm đỏ 9px, `.revealed` là số trong capsule
///   đỏ — chữ luôn một dòng. Ở `.peeking`, tâm nút nằm đúng trên mép nên chỉ báo **lật sang phía còn nhìn thấy**.
/// - **AI đang chạy**: viền tím **tĩnh**. Không xoay sparkles: animation SwiftUI `repeatForever` chạy theo
///   từng frame, tốn năng lượng (cùng lý do `rules.md` cấm ở widget TTS).
/// - **Trình duyệt nháy** (tab thu nhỏ quá 10 s, `VisibleBrowserPulseMonitor`): nền nội suy **màu** đỏ sẫm ↔
///   đỏ tươi, alpha luôn 1. **Không bao giờ** đổi opacity: `FloatingHubUIWindow.hitTest` có guard
///   `alpha > 0.01`, hạ alpha là nút mất chạm.
/// - Trình duyệt **không** có badge số tab hay chấm đỏ (người dùng chốt).
///
/// View này **chỉ vẽ**: vị trí, kéo/thả và chạm do `FloatingHubContainerViewController` (UIKit) xử lý, nhờ vậy
/// ngón tay không trễ theo vòng cập nhật state của SwiftUI. `onActivate` chỉ dùng cho VoiceOver.
struct FloatingHubButton: View {
    /// Cỡ nút, dùng chung cho cả hai trạng thái.
    static let size: CGFloat = 36

    let state: FloatingHubPresentationReader.ButtonState
    let mode: WidgetMode
    /// Mép nút đang dán — quyết định phía đặt chỉ báo chưa đọc.
    let edge: EdgeDirection
    /// Hành động chính (cùng đường với chạm): bung, mở mục, hoặc mở menu.
    let onActivate: () -> Void

    @ObservedObject private var pulseMonitor = VisibleBrowserPulseMonitor.shared

    /// Pha của nhịp nháy: `true` = đỏ tươi, `false` = đỏ sẫm. Chỉ có nghĩa khi `isPulsing == true`.
    @State private var isPulseBright = false

    var body: some View {
        ZStack(alignment: badgeAlignment) {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: Self.size, height: Self.size)
                .overlay {
                    if isPulsing {
                        Circle().fill(pulseColor)
                    }
                }
                .overlay(border)
                .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 3)

            Image(systemName: glyphName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(width: Self.size, height: Self.size)

            if state.unreadCount > 0 {
                badge
            }
        }
        .frame(width: Self.size, height: Self.size)
        .animation(
            isPulsing
                ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                : .easeInOut(duration: 0.2),
            value: pulseLevel
        )
        .onAppear { isPulseBright = isPulsing }
        .onChange(of: isPulsing) { _, newValue in
            isPulseBright = newValue
        }
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        // Kích hoạt bằng VoiceOver không chắc đi qua `UITapGestureRecognizer` của container.
        .accessibilityAction {
            onActivate()
        }
    }

    // MARK: - Glyph & viền

    private var glyphName: String {
        guard state.kinds.count == 1, let kind = state.kinds.first else {
            return "square.grid.2x2"
        }
        return kind.systemImage(unreadCount: state.unreadCount)
    }

    private var glyphColor: Color {
        if isPulsing { return .white }
        guard state.kinds.count == 1, let kind = state.kinds.first else { return .primary }
        return kind.tint
    }

    /// AI đang chạy ⇒ viền tím 2pt thay viền trắng. Tĩnh, không animation.
    @ViewBuilder
    private var border: some View {
        if state.kinds.contains(.ai) {
            Circle().stroke(Color.purple.opacity(0.8), lineWidth: 2)
        } else {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
    }

    // MARK: - Chỉ báo chưa đọc

    /// Chỉ bung mới có số; thu gọn thì chấm đỏ. Cùng ngữ nghĩa với badge chấm ở tab Kệ Sách.
    @ViewBuilder
    private var badge: some View {
        if mode == .revealed {
            Text(state.unreadCount > 99 ? "99+" : "\(state.unreadCount)")
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

    /// Bung: góc trên-phải như badge thông thường. Thu gọn: lật về phía **còn nhìn thấy**.
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

    // MARK: - Nháy trình duyệt

    /// Chỉ nháy khi mục Trình duyệt có mặt. Theo `VisibleBrowserPulseMonitor`, `isPulsing` đã kéo theo
    /// "đang thu nhỏ và còn tab", nên vế đầu chỉ là chốt an toàn.
    private var isPulsing: Bool {
        state.kinds.contains(.browser) && pulseMonitor.isPulsing
    }

    /// 0 = đỏ sẫm nhất, 1 = đỏ tươi nhất. Dùng làm giá trị cho `animation(value:)` và để nội suy màu —
    /// **không** bao giờ dùng làm opacity.
    private var pulseLevel: Double {
        guard isPulsing else { return 0 }
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

    // MARK: - Accessibility

    private var accessibilityText: String {
        let names = state.kinds.map(\.title).joined(separator: ", ")
        var text = "Lối tắt nổi: \(names)"
        if state.unreadCount > 0 {
            text += ", \(state.unreadCount) thông báo chưa đọc"
        }
        return text
    }
}
