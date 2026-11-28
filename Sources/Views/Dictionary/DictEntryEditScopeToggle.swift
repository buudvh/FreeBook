import SwiftUI

/// Cụm **R | C** (Riêng truyện | Chung) đặt cuối hàng aa…AA của màn Sửa từ chế độ danh sách
/// (`DictEntryEditListMode.caseRowTrailing`) — hậu tố / tiền tố của lọc name local mở từ một truyện (2026-11-28, mockup
/// https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M5 / M5b). Chép **kiểu** cụm R | C của panel Dịch Reader
/// (`ReaderDefinitionOverlayView.dictSegmentButton`: nút rộng cố định 30 pt, chữ 13 pt, nền nhóm xám mờ bo 6, nút đang chọn
/// nền xám đậm hơn) nhưng **không ghim** và chữ theo màu hệ thống (panel Reader tô theo nền đọc) — nút của Reader là hàm của
/// view đó, gắn `selectedTheme` + cử chỉ ghim nên không dùng lại trực tiếp được.
struct DictEntryEditScopeToggle: View {
    /// `true` = R (Riêng truyện), `false` = C (Chung).
    @Binding var isBookScope: Bool

    private static let buttonWidth: CGFloat = 30

    var body: some View {
        HStack(spacing: 0) {
            segment("R", isSelected: isBookScope, accessibility: "Riêng truyện") { isBookScope = true }
            Divider()
                .frame(height: 14)
            segment("C", isSelected: !isBookScope, accessibility: "Chung mọi truyện") { isBookScope = false }
        }
        .padding(2)
        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Phạm vi lưu")
    }

    private func segment(
        _ title: String,
        isSelected: Bool,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .primary : .secondary)
                .frame(width: Self.buttonWidth)
                .padding(.vertical, 6)
                .background(isSelected ? Color.secondary.opacity(0.25) : Color.clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
