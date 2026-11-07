import SwiftUI

/// Bốn thanh "Cỡ" của trang Khám phá (Lưới · Hàng ngang · Danh sách & Xếp hạng · Banner) cho **một** loại nguồn.
/// Dùng chung cho sheet "Kiểu hiển thị" mở từ Khám phá (`BookListLayoutSheet(showsExploreSizes: true)`) và màn
/// Cài đặt (`BookListLayoutSettingsView`); trong `Form` mỗi thanh là một hàng. Tiêu đề nhóm do nơi dùng đặt.
///
/// Đọc cỡ **trong lượt vẽ** (bảng là `@Observable` nên ghi xong là vẽ lại).
struct ExploreLayoutSizeControls: View {
    let scope: BookListLayoutScope

    var body: some View {
        let sizes = ExploreLayoutSizePreferences.shared.sizes(for: scope)
        let currentScope = scope
        ForEach(ExploreLayoutSizeKind.allCases) { kind in
            LayoutLevelSlider(
                title: kind.label,
                level: sizes[kind].level,
                range: ExploreLayoutSize.range,
                defaultLevel: ExploreLayoutSize.defaultLevel
            ) { level in
                ExploreLayoutSizePreferences.shared.setLevel(level, kind: kind, for: currentScope)
            }
        }
    }
}
