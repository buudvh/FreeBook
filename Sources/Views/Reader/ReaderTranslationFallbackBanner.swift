import SwiftUI

/// Dải báo ở đầu nội dung chương khi tiện ích dịch lỗi ở một số dòng và chương đang hiện bản QT thay thế (hoặc giữ chữ
/// gốc). Đọc `TranslationFallbackStatusStore` **trong body của chính view này** để chỉ dải vẽ lại khi báo đổi —
/// `ParagraphCardView` bọc ngoài là `.equatable()` nên có thể không tính lại body.
///
/// Không có báo ⇒ không vẽ gì (khoảng cách dưới dải nằm trong dải nên không để lại khe).
struct ReaderTranslationFallbackBanner: View {
    let bookId: String
    let chapterIndex: Int
    let theme: ReaderTheme

    var body: some View {
        if let status = TranslationFallbackStatusStore.shared.status(bookId: bookId, chapterIndex: chapterIndex) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.titleText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textColor)
                    Text(status.detailText)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textColor.opacity(0.7))
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    TranslationFallbackStatusStore.shared.requestRetry(bookId: bookId, chapterIndex: chapterIndex)
                } label: {
                    Text("Thử lại")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textColor)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 11)
                        .background(theme.textColor.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.5)
            )
            .padding(.bottom, 12)
        }
    }
}
