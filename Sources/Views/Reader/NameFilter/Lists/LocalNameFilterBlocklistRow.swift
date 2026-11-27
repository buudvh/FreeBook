import SwiftUI

/// Một hàng của màn **Không phải name** (`LocalNameFilterBlocklistView`, mockup khung 6), kiểu VP/Name: dòng 1 cụm chữ Hán
/// `.headline`, dòng 2 "âm Hán-Việt · thêm dd/MM" `.subheadline` màu phụ, nút `[Xoá]` `.borderless`. Chạm thân hàng mở màn
/// Sửa từ (`LocalNameFilterBlocklistEditorSheet`) — chạm gắn lên khối chữ, không bọc cả hàng trong `Button` (List kích hoạt
/// mọi nút).
struct LocalNameFilterBlocklistRow: View {
    let term: String
    let subtitle: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: term)
                    .font(.headline)
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Xoá \(term) khỏi danh sách")
        }
        .padding(.vertical, 2)
        .accessibilityAction(named: "Sửa", onEdit)
    }
}
