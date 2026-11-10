import SwiftUI

/// Bốn thanh "Cỡ" của trang Khám phá (Lưới · Hàng ngang · Danh sách & Xếp hạng · Banner) cho **một** loại nguồn, ở màn
/// Cài đặt (`BookListLayoutSettingsView`); trong `Form` mỗi thanh là một hàng. Tiêu đề nhóm do nơi dùng đặt. Sheet "Kiểu
/// hiển thị" mở từ Khám phá dùng `ExploreLayoutSizePicker` (hàng chọn + một thanh, 1.3.823) cho gọn nửa màn.
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
