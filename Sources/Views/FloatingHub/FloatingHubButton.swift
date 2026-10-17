import SwiftUI

/// Nút tròn 36px của hub nổi (1.3.524) — cùng khuôn nút thông báo / trình duyệt cũ: nền `.ultraThinMaterial`,
/// viền trắng 20 %, bóng đen 24 %.
///
/// Từ 1.3.533 hub **luôn hiện** (trừ lúc cổng từ điển chưa mở, sheet của hub đang mở, hoặc trình phát video
/// đang toàn màn), kể cả khi không mục nào hoạt động.
///
/// ## Glyph theo số mục đang hoạt động
/// - Đúng 1 mục: glyph của chính mục đó (`sparkles` tím / `bell.fill` hoặc `bell` / `play.rectangle`).
/// - 0 hoặc từ 2 mục: `square.grid.2x2`.
///
/// ## Chỉ báo
/// - **Badge = số mục đang hoạt động** (dòng sáng trong menu). `.peeking` là chấm đỏ 9px, `.revealed` là số
///   trong capsule đỏ — chữ luôn một dòng. Ở `.peeking`, tâm nút nằm đúng trên mép nên chỉ báo **lật sang
///   phía còn nhìn thấy**. Số chưa đọc của Thông báo nằm ở badge của dòng trong menu, không ở đây.
/// - **AI đang chạy**: viền tím **tĩnh**. Không xoay sparkles: animation SwiftUI `repeatForever` chạy theo
///   từng frame, tốn năng lượng (cùng lý do `rules.md` cấm ở widget TTS).
/// - Nhịp nháy đỏ của trình duyệt thu nhỏ đã theo trình duyệt về cửa sổ riêng (`VisibleBrowserReopenButton`).
///
/// View này **chỉ vẽ**: vị trí, kéo/thả và chạm do `FloatingHubContainerViewController` (UIKit) xử lý, nhờ vậy
/// ngón tay không trễ theo vòng cập nhật state của SwiftUI. `onActivate` chỉ dùng cho VoiceOver.
struct FloatingHubButton: View {
    /// Cỡ nút, dùng chung cho cả hai trạng thái.
    static let size: CGFloat = 36

    let state: FloatingHubPresentationReader.ButtonState
    let mode: WidgetMode
    /// Mép nút đang dán — quyết định phía đặt chỉ báo.
    let edge: EdgeDirection
    /// Hành động chính (cùng đường với chạm): bung và mở menu, hoặc đóng menu.
    let onActivate: () -> Void

    var body: some View {
        ZStack(alignment: badgeAlignment) {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: Self.size, height: Self.size)
                .overlay(border)
                .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 3)

            Image(systemName: glyphName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(width: Self.size, height: Self.size)

            if state.activeCount > 0 {
                badge
            }
        }
        .frame(width: Self.size, height: Self.size)
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

    private var singleActiveKind: FloatingHubItem.Kind? {
        state.activeKinds.count == 1 ? state.activeKinds.first : nil
    }

    private var glyphName: String {
        guard let kind = singleActiveKind else { return "square.grid.2x2" }
        return kind.systemImage(unreadCount: state.unreadCount)
    }

    private var glyphColor: Color {
        guard let kind = singleActiveKind else { return .primary }
        return kind.tint
    }

    /// AI đang chạy ⇒ viền tím 2pt thay viền trắng. Tĩnh, không animation.
    @ViewBuilder
    private var border: some View {
        if state.activeKinds.contains(.ai) {
            Circle().stroke(Color.purple.opacity(0.8), lineWidth: 2)
        } else {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
    }

    // MARK: - Chỉ báo số mục đang hoạt động

    /// Chỉ bung mới có số; thu gọn thì chấm đỏ.
    @ViewBuilder
    private var badge: some View {
        if mode == .revealed {
            Text("\(state.activeCount)")
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

    // MARK: - Accessibility

    private var accessibilityText: String {
        guard !state.activeKinds.isEmpty else {
            return "Lối tắt nổi: không có mục đang hoạt động"
        }
        let names = state.activeKinds.map(\.title).joined(separator: ", ")
        var text = "Lối tắt nổi: \(names)"
        if state.unreadCount > 0 {
            text += ", \(state.unreadCount) thông báo chưa đọc"
        }
        return text
    }
}
