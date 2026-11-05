import SwiftUI

/// Icon lọc (phễu — `FilterGlyph`) của một tiện ích ở các màn danh sách: header Khám phá (`.circle`), thanh tiêu đề trang
/// danh sách thể loại / nhãn (`.toolbar`), cạnh ô tìm khi tìm trong một nguồn (`.inline`). Không vẽ gì khi script của tab
/// (`scope`, cùng các file nó `load`) không dùng mục `select` / công tắc / `list` nào của `config` (hoặc chưa đọc xong —
/// `ExtensionFilterCatalog`); chấm khi bộ lọc của tab khác mặc định. Bấm ⇒ `action` (màn chứa mở `ExtensionFilterSheet`
/// cùng `scope`).
struct ExtensionFilterButton: View {
    /// Bản ghi **mới nhất** của tiện ích (tra lại theo `packageId` ở màn chứa) — config đổi thì chấm cập nhật.
    let ext: Extension?
    let scope: ExtensionFilterScope
    var style: FilterGlyph.Style = .toolbar
    let action: () -> Void

    var body: some View {
        if let ext, let info = ExtensionFilterCatalog.shared.info(for: ext, scope: scope), info.hasFilters {
            Button(action: action) {
                FilterGlyph(style: style, isActive: info.isActive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(info.isActive ? "Bộ lọc (đang lọc)" : "Bộ lọc")
        }
    }
}
