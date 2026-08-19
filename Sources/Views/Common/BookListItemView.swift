import SwiftUI

/// Dữ liệu hiển thị tối thiểu của một cuốn sách, dùng chung cho
/// `Book` (SwiftData) và `ExtensionItemResult` (DTO discovery/genre).
protocol BookDisplayable {
    var bookId: String { get }
    var title: String { get }
    var author: String { get }
    var coverUrl: String { get }
    var sourceName: String { get }
    var description: String { get }
    var currentChapterTitle: String { get }
    var currentChapterIndex: Int { get }
    var isLocalBook: Bool { get }
}

extension BookDisplayable {
    var isLocalBook: Bool { false }
}

/// Row hiển thị một cuốn sách (cover + title dịch + author/source hoặc description),
/// dùng chung cho Kệ sách (ShelfView), sheet chọn truyện (BookShareTargetSheet),
/// danh sách genre (CategoryNovelsListView) và màn hình discovery (DiscoveryCategoryTabView).
struct BookListItemView<Item: BookDisplayable>: View {
    let item: Item
    var showChapter: Bool = true
    var showDescription: Bool = false
    var coverWidth: CGFloat = 50
    var coverHeight: CGFloat = 70

    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false

    var body: some View {
        HStack(spacing: 12) {
            BookCoverView(bookId: item.bookId, coverUrl: item.coverUrl, width: coverWidth, height: coverHeight)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 4) {
                Text(DisplayTextFormatter.titleCase(translateIfNeeded(item.title, bookId: item.bookId)))
                    .font(.headline)
                    .lineLimit(2)

                if showDescription, !item.description.isEmpty {
                    Text(translateIfNeeded(item.description.cleanHTML()))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else {
                    HStack(spacing: 8) {
                        if !item.author.isEmpty {
                            Text(DisplayTextFormatter.titleCase(TranslateUtils.translateAuthorHanViet(item.author)))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if item.isLocalBook {
                            Text("Local")
                                .font(.caption2)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        } else if !item.sourceName.isEmpty {
                            Text(item.sourceName)
                                .font(.caption2)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }
                }

                if showChapter {
                    let rawChapterTitle = item.currentChapterTitle.isEmpty
                        ? "Chương \(item.currentChapterIndex + 1)"
                        : item.currentChapterTitle
                    let chapterTitle = isTranslationEnabled
                        ? translateChapterTitleIfNeeded(rawChapterTitle, bookId: item.bookId)
                        : rawChapterTitle

                    if !chapterTitle.isEmpty {
                        Text("Đang đọc: \(chapterTitle)")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

extension Book: BookDisplayable {
    var description: String { desc }
}

extension ExtensionItemResult: BookDisplayable {
    var bookId: String { link }
    var title: String { name }
    var coverUrl: String { cover }
    var sourceName: String { "" }
    var currentChapterTitle: String { "" }
    var currentChapterIndex: Int { 0 }
}
