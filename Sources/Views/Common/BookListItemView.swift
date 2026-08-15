import SwiftUI

/// Row hiển thị một cuốn sách (cover + title dịch + tác giả + nguồn truyện),
/// dùng chung cho Kệ sách (ShelfView) và các sheet chọn truyện (BookShareTargetSheet).
struct BookListItemView: View {
    let book: Book
    var showChapter: Bool = true

    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false

    var body: some View {
        HStack(spacing: 12) {
            BookCoverView(bookId: book.bookId, coverUrl: book.coverUrl, width: 50, height: 70)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 4) {
                Text(DisplayTextFormatter.titleCase(translateIfNeeded(book.title, bookId: book.bookId)))
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if !book.author.isEmpty {
                        Text(DisplayTextFormatter.titleCase(TranslateUtils.translateAuthorHanViet(book.author)))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Text(book.sourceName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }

                if showChapter {
                    let rawChapterTitle = book.currentChapterTitle.isEmpty
                        ? "Chương \(book.currentChapterIndex + 1)"
                        : book.currentChapterTitle
                    let chapterTitle = isTranslationEnabled
                        ? translateChapterTitleIfNeeded(rawChapterTitle, bookId: book.bookId)
                        : rawChapterTitle

                    if !chapterTitle.isEmpty {
                        Text("Đang đọc: \(chapterTitle)")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
    }

    private func translateIfNeeded(_ text: String, bookId: String? = nil) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text, bookId: bookId)
    }

    private func translateChapterTitleIfNeeded(_ text: String, bookId: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateChapterTitle(text, bookId: bookId)
    }
}
