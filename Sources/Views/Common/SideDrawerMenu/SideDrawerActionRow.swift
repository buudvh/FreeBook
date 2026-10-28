import SwiftUI

/// Hàng thao tác của ngăn kéo: bấm ⇒ ngăn kéo bắt đầu trượt ra và `action` chạy **ngay** — ngăn kéo nằm ở cửa sổ nổi
/// riêng nên màn bên dưới mở sheet / alert / confirmationDialog / bộ chọn tệp / điều hướng được luôn, hiện lên phía
/// dưới trong lúc ngăn kéo trượt đi.
///
/// `role: .destructive` ⇒ chữ và icon màu đỏ. `.disabled(...)` gắn ngoài hàng thì hàng mờ đi và không bấm được.
struct SideDrawerActionRow: View {
    let title: String
    let icon: SideDrawerMenuIcon
    let detail: String?
    let role: ButtonRole?
    let action: () -> Void

    @Environment(\.sideDrawerMenuDismiss) private var dismissDrawer

    init(
        _ title: String,
        systemImage: String,
        detail: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.init(title, icon: .system(systemImage), detail: detail, role: role, action: action)
    }

    /// Icon là `AppGlyph` (asset template) thay vì SF Symbol.
    init(
        _ title: String,
        glyph: AppGlyph,
        detail: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.init(title, icon: .asset(glyph.assetName), detail: detail, role: role, action: action)
    }

    init(
        _ title: String,
        icon: SideDrawerMenuIcon,
        detail: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.detail = detail
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role) {
            dismissDrawer(then: action)
        } label: {
            SideDrawerMenuRowLabel(icon: icon, title: title, tint: role == .destructive ? Color.red : Color.white) {
                if let detail {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .buttonStyle(SideDrawerRowButtonStyle())
    }
}
