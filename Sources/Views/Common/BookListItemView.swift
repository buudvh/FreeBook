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
    var extensionLocalPath: String { get }
    var extensionIconUrl: String? { get }
}

extension BookDisplayable {
    var isLocalBook: Bool { false }
    var extensionLocalPath: String { "" }
    var extensionIconUrl: String? { nil }
}

/// Phong cách hiển thị của một row truyện. Cover và title đồng bộ ở mọi style;
/// chỉ khác phần thông tin phụ bên dưới title.
enum BookListItemStyle {
    /// Kệ sách / Lịch sử đọc / sheet chọn truyện: author (Hán-Việt) + pill nguồn + dòng "Đang đọc".
    case shelfOrHistory
    /// Discovery / genre: hiển thị description thay cho author/source.
    case discovery
}

/// Row hiển thị một cuốn sách (cover + title dịch + author/source hoặc description),
/// dùng chung cho Kệ sách (ShelfView), sheet chọn truyện (BookShareTargetSheet),
/// danh sách genre (CategoryNovelsListView) và màn hình discovery (DiscoveryCategoryTabView).
struct BookListItemView<Item: BookDisplayable>: View {
    let item: Item
    var showChapter: Bool
    var showDescription: Bool
    var coverWidth: CGFloat
    var coverHeight: CGFloat
    var extensionLocalPath: String
    var extensionIconUrl: String?

    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false

    init(
        item: Item,
        style: BookListItemStyle = .shelfOrHistory,
        showChapter: Bool? = nil,
        showDescription: Bool? = nil,
        coverWidth: CGFloat = 50,
        coverHeight: CGFloat = 70,
        extensionLocalPath: String = "",
        extensionIconUrl: String? = nil
    ) {
        self.item = item
        switch style {
        case .shelfOrHistory:
            self.showChapter = showChapter ?? true
            self.showDescription = showDescription ?? false
        case .discovery:
            self.showChapter = showChapter ?? false
            self.showDescription = showDescription ?? true
        }
        self.coverWidth = coverWidth
        self.coverHeight = coverHeight
        self.extensionLocalPath = extensionLocalPath
        self.extensionIconUrl = extensionIconUrl
    }

    var body: some View {
        HStack(spacing: 12) {
            BookCoverView(bookId: item.bookId, coverUrl: item.coverUrl, width: coverWidth, height: coverHeight)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 4) {
                Text(DisplayTextFormatter.titleCase(translateIfNeeded(item.title, bookId: item.bookId)))
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(2)

                if showDescription, !item.description.isEmpty {
                    Text(translateIfNeeded(item.description.cleanHTML()))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else {
                    let hasAuthor = !item.author.isEmpty
                    let hasSource = item.isLocalBook || !item.sourceName.isEmpty
                    if hasAuthor || hasSource {
                        HStack(spacing: 8) {
                            if hasAuthor {
                                Text(DisplayTextFormatter.titleCase(displayedAuthor))
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            if item.isLocalBook {
                                sourceBadge(text: "Local")
                            } else if !item.sourceName.isEmpty {
                                sourceBadge(text: item.sourceName)
                            }
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
                            .font(.caption2)
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private func translateIfNeeded(_ text: String, bookId: String? = nil) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text, bookId: bookId)
    }

    private var displayedAuthor: String {
        guard isTranslationEnabled else { return item.author }
        return TranslateUtils.translateAuthorHanViet(item.author)
    }

    private func translateChapterTitleIfNeeded(_ text: String, bookId: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateChapterTitle(text, bookId: bookId)
    }

    private func sourceBadge(text: String) -> some View {
        HStack(spacing: 4) {
            if !extensionLocalPath.isEmpty {
                ExtensionIconView(localPath: extensionLocalPath, iconUrl: extensionIconUrl ?? "", size: 14)
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .resizable()
                    .frame(width: 12, height: 12)
                    .foregroundColor(.secondary)
            }
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12), in: Capsule())
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
