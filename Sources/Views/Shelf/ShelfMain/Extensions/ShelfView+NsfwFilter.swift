import SwiftUI

/// Nhóm **"NSFW"** trong ngăn kéo "…" của tab Kệ Sách (1.3.778): ba hàng chọn của bộ lọc NSFW riêng của Kệ + Lịch sử
/// (`ShelfNsfwFilter`) — thay công tắc NSFW chung cũ ở ngăn kéo này. Đọc / ghi `ShelfNsfwFilterState` (singleton, không qua
/// state của màn) nên ngăn kéo ở cửa sổ riêng vẫn thấy dấu tích mới sau `refreshContent()` của `SideDrawerOptionRow`.
extension ShelfView {
    @ViewBuilder
    func shelfNsfwFilterRows() -> some View {
        let state = ShelfNsfwFilterState.shared
        SideDrawerDivider()
        SideDrawerSectionHeader("NSFW")
        ForEach(ShelfNsfwFilter.allCases, id: \.self) { mode in
            SideDrawerOptionRow(mode.title, isSelected: state.mode == mode) {
                state.select(mode)
            }
        }
    }
}
