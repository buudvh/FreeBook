import SwiftUI

/// Hàng thao tác **có dòng phụ dưới tiêu đề** cho ngăn kéo ⋯ của trang Lịch sử lọc (mockup H4: "Dọn dẹp tất cả" đỏ, dòng
/// phụ "12 lần · 2 gói tạm chưa lưu"). `SideDrawerActionRow` chỉ có chữ phụ bên phải, một dòng, không co — chữ dài như vậy
/// đè mất tiêu đề — nên hàng này dựng riêng theo đúng số đo của `SideDrawerMenuRowLabel` (cột icon 26, lề 16, cách 12, cao
/// ≥ 46) và cùng cách đóng ngăn kéo (`sideDrawerMenuDismiss`: action chạy ngay khi ngăn kéo bắt đầu trượt ra).
struct LocalNameFilterHistoryDrawerRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let role: ButtonRole?
    let action: () -> Void

    @Environment(\.sideDrawerMenuDismiss) private var dismissDrawer
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let tint = role == .destructive ? Color.red : Color.white
        Button(role: role) {
            dismissDrawer(then: action)
        } label: {
            HStack(spacing: 12) {
                SideDrawerMenuIcon.system(systemImage).image(size: 17)
                    .foregroundStyle(tint)
                    .frame(width: 26)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(minHeight: 46)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(SideDrawerRowButtonStyle())
    }
}
