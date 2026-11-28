import SwiftUI

/// Hàng chip lọc theo loại của màn **Hậu tố** / **Tiền tố** (`LocalNameFilterSuffixListView`, plan 2026-11-27-phan-loai-name
/// L11 — danh sách hậu tố lớn lên ~1.300 dòng): "Tất cả 1.299 · Địa danh 42 · Tổ chức 27 · Thuật ngữ 40 · Nhân danh 1.190"
/// (mockup khung 6), thay cho thanh tab cũ. Chỉ hiện loại có mục (danh sách tiền tố gốc chỉ có Nhân danh), cộng loại đang
/// chọn để chip đang bật không biến mất.
///
/// Chip đang chọn theo kiểu `ExtensionKindFilterBar` (chữ màu nhấn, nền nhấn mờ 18%, viền 60%); chip thường nền
/// `Color.primary` mờ như chip loại của màn duyệt (`ReaderAINameReviewCategoryBar`) — nền hệ thống đặc trông lạc trên sheet
/// kính. Số đếm định dạng kiểu Việt ("1.299", `formattedCount`) — hàng danh sách ở sheet Lọc name local dùng chung.
struct LocalNameFilterAffixKindFilterBar: View {
    let entries: [LocalNameFilterSuffixEntry]
    /// `nil` = Tất cả.
    @Binding var selection: LocalNameFilter.SuffixKind?

    /// Số có dấu chấm ngăn hàng nghìn kiểu Việt, không theo ngôn ngữ máy: 1299 ⇒ "1.299".
    static func formattedCount(_ count: Int) -> String {
        count.formatted(.number.locale(Locale(identifier: "vi_VN")))
    }

    var body: some View {
        let counts = Dictionary(grouping: entries, by: \.kind).mapValues(\.count)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Self.chip(title: "Tất cả \(Self.formattedCount(entries.count))", isSelected: selection == nil) {
                    selection = nil
                }
                ForEach(LocalNameFilter.SuffixKind.allCases, id: \.self) { kind in
                    let count = counts[kind] ?? 0
                    if count > 0 || selection == kind {
                        Self.chip(
                            title: "\(LocalNameFilterSuffixRow.kindLabel(kind)) \(Self.formattedCount(count))",
                            isSelected: selection == kind
                        ) {
                            selection = kind
                        }
                    }
                }
            }
            .padding(.horizontal, HeaderMetrics.horizontalMargin)
            .padding(.vertical, 6)
        }
    }

    /// Một chip của hàng (cũng dùng cho hàng chip phạm vi "Chung · Riêng truyện" của màn danh sách).
    static func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .foregroundColor(isSelected ? .accentColor : .primary)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.12), lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
