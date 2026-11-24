import SwiftUI

/// Dải dài viền màu nhấn trên lưới thao tác của sheet nhấn giữ truyện (1.3.1014): "Đổi nguồn" (anh Bửu: "để nút đổi nguồn
/// giống 'Chuyển sang nguồn …' trong mockup") và "Chuyển sang nguồn …" của truyện mất nguồn
/// (`MissingSourceRebindActionRows`). Icon + chữ màu nhấn, nền nhấn mờ 16%, viền nhấn 55% — kiểu chip đang chọn của app.
/// `.buttonStyle(.plain)` vì nằm chung một hàng `List` với lưới ô. Có `subtitle` ⇒ hai dòng, tên đậm hơn (dải "Đọc tiếp",
/// `BookContinueReadingStrip`).
struct BookActionStrip: View {
    let title: String
    let systemImage: String
    /// Dòng phụ màu phụ dưới tên; `nil` ⇒ một dòng như cũ.
    var subtitle: String? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(subtitle == nil ? .medium : .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle {
                        // `Color.secondary` chứ không `.secondary`: kiểu phân cấp sẽ là màu nhấn mờ của dải.
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, subtitle == nil ? 11 : 9)
            .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}
