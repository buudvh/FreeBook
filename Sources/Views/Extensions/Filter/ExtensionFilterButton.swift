import SwiftUI

/// Icon lọc của một tiện ích ở các màn danh sách: header Khám phá (`.circle`), thanh tiêu đề trang danh sách thể loại /
/// nhãn (`.toolbar`), cạnh ô tìm khi tìm trong một nguồn (`.inline`). Không vẽ gì khi `config` của tiện ích không có
/// mục `select` / công tắc / `list` (hoặc chưa đọc xong — `ExtensionFilterCatalog`); chấm trắng khi bộ lọc khác mặc
/// định. Bấm ⇒ `action` (màn chứa mở `ExtensionFilterSheet`).
struct ExtensionFilterButton: View {
    enum Style {
        /// Nút tròn 38 có nền, cùng cụm nút tròn của header Khám phá.
        case circle
        /// Icon 17pt khung `pairIconWidth` × 36, đứng cặp với nút khác trong một `ToolbarItem`.
        case toolbar
        /// Icon 17pt khung 36 × 40, đứng cạnh ô tìm dạng viên thuốc.
        case inline
    }

    /// Bản ghi **mới nhất** của tiện ích (tra lại theo `packageId` ở màn chứa) — config đổi thì chấm cập nhật.
    let ext: Extension?
    var style: Style = .toolbar
    let action: () -> Void

    var body: some View {
        if let ext, let info = ExtensionFilterCatalog.shared.info(for: ext), info.hasFilters {
            Button(action: action) {
                icon(isActive: info.isActive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(info.isActive ? "Bộ lọc (đang lọc)" : "Bộ lọc")
        }
    }

    @ViewBuilder
    private func icon(isActive: Bool) -> some View {
        let glyph = Image(systemName: "line.3.horizontal.decrease")
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.primary)
        switch style {
        case .circle:
            glyph
                .frame(width: 38, height: 38)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())
                .overlay(alignment: .topTrailing) { activeDot(isActive).padding(7) }
        case .toolbar:
            glyph
                .frame(width: HeaderButtonMetrics.pairIconWidth, height: 36)
                .overlay(alignment: .topTrailing) { activeDot(isActive).padding(.top, 6).padding(.trailing, 2) }
                .contentShape(Rectangle())
        case .inline:
            glyph
                .frame(width: 36, height: 40)
                .overlay(alignment: .topTrailing) { activeDot(isActive).padding(.top, 8).padding(.trailing, 4) }
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func activeDot(_ isActive: Bool) -> some View {
        if isActive {
            Circle()
                .fill(Color.white)
                .frame(width: 7, height: 7)
        }
    }
}
