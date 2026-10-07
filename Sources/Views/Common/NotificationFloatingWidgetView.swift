import SwiftUI

/// Nút chuông nổi của widget thông báo: **một** cỡ duy nhất **36px** cho cả hai trạng thái, glyph chuông
/// 17pt — đúng cỡ glyph của nút chuông đang nằm ở toolbar Kệ Sách (`ShelfView.swift:180-181`), nên hai lối
/// vào trông như cùng một nút (người dùng chốt 2026-10-07).
///
/// ## Hai trạng thái khác nhau ở đâu
/// Không khác kích thước, chỉ khác **vị trí** (do `NotificationFloatingWidgetContainerViewController` quyết
/// định: ngậm 1/3 vào mép hay nằm trong màn) và **kiểu badge**:
/// - `.revealed` — badge là **số** (`> 99` hiện `99+`).
/// - `.peeking` — badge thu thành **chấm đỏ 9px**.
///
/// ## Badge phải đổi phía theo mép
/// Ở `.peeking`, tâm nút nằm **đúng trên mép màn hình** nên một nửa nút ra ngoài. Badge đặt cố định ở
/// góc trên-phải sẽ bị đẩy ra ngoài khi nút dán mép phải — đúng lúc badge là thứ duy nhất còn đáng nhìn.
/// Vì vậy badge lật sang góc trên-**trái** khi nút ở mép phải.
///
/// View này **chỉ vẽ**: kéo, thả, snap và chạm do container VC xử lý (UIKit), đúng khuôn
/// `VisibleBrowserReopenButton` — nhờ vậy ngón tay không trễ theo vòng cập nhật state của SwiftUI.
struct NotificationFloatingWidgetButton: View {
    /// Cỡ nút, dùng chung cho cả hai trạng thái.
    static let size: CGFloat = 36

    let unreadCount: Int
    let mode: WidgetMode
    /// Mép nút đang dán — quyết định phía đặt badge.
    let edge: EdgeDirection

    var body: some View {
        ZStack(alignment: badgeAlignment) {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: Self.size, height: Self.size)
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 3)

            Image(systemName: unreadCount > 0 ? "bell.badge.fill" : "bell")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: Self.size, height: Self.size)

            if unreadCount > 0 {
                badge
            }
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    /// Chỉ bung mới có số; thu gọn thì chấm đỏ. Cùng ngữ nghĩa với badge chấm ở tab Kệ Sách.
    @ViewBuilder
    private var badge: some View {
        if mode == .revealed {
            Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
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

    /// Bung: badge ở góc trên-phải như badge thông thường. Thu gọn: lật về phía **còn nhìn thấy**.
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

    private var accessibilityText: String {
        unreadCount > 0
            ? "Trung tâm thông báo, \(unreadCount) thông báo chưa đọc"
            : "Trung tâm thông báo"
    }
}
