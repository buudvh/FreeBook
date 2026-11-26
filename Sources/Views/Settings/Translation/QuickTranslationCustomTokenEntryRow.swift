import SwiftUI

/// Một hàng của màn danh sách từ của token tùy chọn (`QuickTranslationCustomTokenEntryListView`, 1.3.1063), kiểu VP/Name:
/// dòng 1 chữ gốc `.headline`, dòng 2 nghĩa `.subheadline` màu phụ, icon `[Xoá]`. Chạm thân hàng mở sheet sửa; không
/// bọc cả hàng trong `Button` (List sẽ kích hoạt mọi nút); trợ năng có thao tác "Sửa".
struct QuickTranslationCustomTokenEntryRow: View {
    let entry: QuickTranslationCustomToken.Entry
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: entry.key)
                        .font(.headline)
                    Text(verbatim: entry.meaning)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture { onEdit() }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Xoá \(entry.key)")
        }
        .padding(.vertical, 2)
        .accessibilityAction(named: "Sửa") { onEdit() }
    }
}
