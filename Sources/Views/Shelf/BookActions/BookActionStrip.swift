import SwiftUI

/// Dải dài viền màu nhấn trên lưới thao tác của sheet nhấn giữ truyện (1.3.1014): "Đổi nguồn" (anh Bửu: "để nút đổi nguồn
/// giống 'Chuyển sang nguồn …' trong mockup") và "Chuyển sang nguồn …" của truyện mất nguồn
/// (`MissingSourceRebindActionRows`). Icon + chữ màu nhấn, nền nhấn mờ 16%, viền nhấn 55% — kiểu chip đang chọn của app.
/// `.buttonStyle(.plain)` vì nằm chung một hàng `List` với lưới ô.
struct BookActionStrip: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
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
