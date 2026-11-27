import SwiftUI

/// Một hàng của màn **Không phải name** (`LocalNameFilterBlocklistView`, mockup khung 6), kiểu VP/Name: dòng 1 cụm chữ Hán
/// `.headline`, dòng 2 "âm Hán-Việt · thêm dd/MM" `.subheadline` màu phụ, nút `[Xoá]` `.borderless`. Không có màn sửa
/// (sửa = xoá rồi thêm lại) nên thân hàng không nhận chạm.
struct LocalNameFilterBlocklistRow: View {
    let term: String
    let subtitle: String
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

            Spacer(minLength: 8)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Xoá \(term) khỏi danh sách")
        }
        .padding(.vertical, 2)
    }
}
