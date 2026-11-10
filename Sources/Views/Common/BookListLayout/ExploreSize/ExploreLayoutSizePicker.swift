import SwiftUI

/// Nhóm "Trang Khám phá" của sheet "Kiểu hiển thị" (`BookListLayoutSheet(showsExploreSizes: true)`, 1.3.823, anh Bửu
/// duyệt mockup): **hàng chọn bố cục** Lưới · Hàng ngang · Danh sách · Banner dáng y hàng Danh sách / Lưới / Chỉ bìa ở
/// trên, dưới là **một** thanh "Cỡ" của bố cục đang chọn + một dòng ghi chú — thay cho bốn thanh xếp chồng (sheet nửa màn
/// phải cuộn mới thấy hết). Bố cục nào đang khác mặc định có chấm màu nhấn ở góc ô (thanh của nó đang ẩn).
///
/// Hàng chọn tự vẽ theo dáng `Picker(.segmented)` của iOS (nền `tertiarySystemFill`, ô chọn trắng / xám đậm, chữ 13 pt)
/// vì ô của `UISegmentedControl` không gắn được chấm. Màn Cài đặt vẫn dùng `ExploreLayoutSizeControls` (bốn thanh, đủ chỗ).
/// Đọc cỡ **trong lượt vẽ** (bảng `@Observable` ⇒ ghi xong là vẽ lại).
struct ExploreLayoutSizePicker: View {
    let scope: BookListLayoutScope

    @State private var selected: ExploreLayoutSizeKind = .grid

    private static let segmentHeight: CGFloat = 28
    private static let selectedFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGray2 : .white
    })

    var body: some View {
        let sizes = ExploreLayoutSizePreferences.shared.sizes(for: scope)
        let currentScope = scope
        let kind = selected
        VStack(alignment: .leading, spacing: 16) {
            segments(sizes)
            VStack(alignment: .leading, spacing: 8) {
                LayoutLevelSlider(
                    title: kind.sliderTitle,
                    level: sizes[kind].level,
                    range: ExploreLayoutSize.range,
                    defaultLevel: ExploreLayoutSize.defaultLevel
                ) { level in
                    ExploreLayoutSizePreferences.shared.setLevel(level, kind: kind, for: currentScope)
                }
                Text(kind.sliderNote)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func segments(_ sizes: ExploreLayoutSizes) -> some View {
        HStack(spacing: 0) {
            ForEach(ExploreLayoutSizeKind.allCases) { kind in
                segment(kind, isChanged: !sizes[kind].isDefault)
            }
        }
        .padding(2)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func segment(_ kind: ExploreLayoutSizeKind, isChanged: Bool) -> some View {
        let isSelected = kind == selected
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selected = kind }
        } label: {
            Text(kind.shortLabel)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: Self.segmentHeight)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Self.selectedFill)
                            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isChanged {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                            .padding(5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.label)
        .accessibilityValue(isChanged ? "Khác mặc định" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
