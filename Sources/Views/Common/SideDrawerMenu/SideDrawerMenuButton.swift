import SwiftUI

/// Nút tự giữ trạng thái mở ngăn kéo, gắn ngăn kéo vào **chính nó** — dành cho hàng của một `Section` dựng lười trong
/// `List`, nơi không có view cha ổn định để gắn `sideDrawerMenu(item:)` (footer/header của section có thể chưa được
/// dựng khi cuộn khuất; gắn lên `Section` thì modifier lan xuống từng hàng). Hàng đang bấm luôn nằm trên màn nên ngăn
/// kéo trình bày được; mỗi hàng một trạng thái riêng nên chỉ một ngăn kéo mở.
///
/// **Không** dùng trong `ToolbarItem` — ở đó gắn `sideDrawerMenu(isPresented:)` vào thân màn (xem
/// `SideDrawerMenuModifier`).
struct SideDrawerMenuButton<ButtonLabel: View, MenuContent: View>: View {
    let title: String
    @ViewBuilder let menuContent: () -> MenuContent
    @ViewBuilder let label: () -> ButtonLabel

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label()
        }
        .sideDrawerMenu(isPresented: $isPresented, title: title, content: menuContent)
    }
}
