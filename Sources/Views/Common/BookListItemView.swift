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
    /// Host của sách/item cho bìa (ghép bìa tương đối + `Referer`). Tên riêng, không trùng `host` của
    /// `Book` (`String?`) / `ExtensionItemResult` (`String`).
    var coverHost: String? { get }
    /// Tiện ích nguồn — lấy `source` khi `coverHost` rỗng.
    var coverPackageId: String { get }
    /// Nhãn ngắn hiện trên bìa (`tag` của item); `""` = không có.
    var coverTag: String { get }
}

extension BookDisplayable {
    var isLocalBook: Bool { false }
    var extensionLocalPath: String { "" }
    var extensionIconUrl: String? { nil }
    var coverHost: String? { nil }
    var coverPackageId: String { "" }
    var coverTag: String { "" }
}

/// Row hiển thị một cuốn sách (cover + title dịch + author/source hoặc description),
/// dùng chung cho Kệ sách (ShelfView), sheet chọn truyện (BookShareTargetSheet),
/// danh sách genre (CategoryNovelsListView) và màn hình discovery (DiscoveryCategoryTabView).
struct BookListItemView<Item: BookDisplayable>: View {
    let item: Item
    var showChapter: Bool
    var showDescription: Bool
    /// Cỡ dòng của kiểu Danh sách (`BookListLayout.rowSize`); nấc mặc định = bìa 50×70 như trước.
    var rowSize: BookListRowSize
    var extensionLocalPath: String
    var extensionIconUrl: String?
    /// Tiện ích nguồn của item khi `item` không tự biết (`ExtensionItemResult` ở Khám phá/thể loại) — để bìa có
    /// `Referer` (`source`) khi item thiếu `host`. Rỗng ⇒ `item.coverPackageId`, rồi tra theo `extensionLocalPath`.
    var extensionPackageId: String

    init(
        item: Item,
        style: BookListItemStyle = .shelfOrHistory,
        showChapter: Bool? = nil,
        showDescription: Bool? = nil,
        rowSize: BookListRowSize = .default,
        extensionLocalPath: String = "",
        extensionIconUrl: String? = nil,
        extensionPackageId: String = ""
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
        self.rowSize = rowSize
        self.extensionLocalPath = extensionLocalPath
        self.extensionIconUrl = extensionIconUrl
        self.extensionPackageId = extensionPackageId
    }

    var body: some View {
        let packageId = coverPackageId
        let kind = ExtensionContentKind.resolve(packageId: packageId)
        // Một lần mỗi hàng: ba cấp của popup dịch + phồn → giản, vẽ lại khi cấu hình đổi (`BookDisplayTranslation`).
        let options = BookDisplayTranslation.listOptions(bookId: item.bookId, packageId: packageId.isEmpty ? nil : packageId)
        HStack(spacing: 12) {
            // Album âm thanh bìa vuông (`BookListRowSize.coverHeight(for:)`, cùng khung với lớp phủ của `ShelfBookRowView`).
            BookCoverView(
                bookId: item.bookId,
                coverUrl: item.coverUrl,
                width: rowSize.coverWidth,
                height: rowSize.coverHeight(for: kind),
                host: item.coverHost,
                extensionPackageId: packageId
            )
            .overlay(alignment: .bottomLeading) {
                CoverTagBadge(tag: item.coverTag)
            }
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 4) {
                Text(BookDisplayTranslation.title(item.title, options))
                    .font(rowSize.font(.system(size: 14.5, weight: .semibold), base: 14.5, weight: .semibold))
                    .lineLimit(rowSize.titleLineLimit)

                if rowSize.isCompact {
                    compactSubtitle(kind: kind, options: options)
                } else if showDescription, !item.description.isEmpty {
                    Text(BookDisplayTranslation.text(item.description.cleanHTML(), options))
                        .font(rowSize.font(.caption2, base: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else {
                    let hasAuthor = !item.author.isEmpty
                    let hasSource = item.isLocalBook || !item.sourceName.isEmpty
                    if hasAuthor || hasSource {
                        HStack(spacing: 8) {
                            if hasAuthor {
                                Text(DisplayTextFormatter.titleCase(BookDisplayTranslation.author(item.author, options)))
                                    .font(rowSize.font(.system(size: 13), base: 13))
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

                if showChapter, !rowSize.isCompact {
                    let isAudio = kind == .audio
                    let rawChapterTitle = item.currentChapterTitle.isEmpty
                        ? "\(isAudio ? "Bài" : "Chương") \(item.currentChapterIndex + 1)"
                        : item.currentChapterTitle
                    let chapterTitle = BookDisplayTranslation.chapterTitle(rawChapterTitle, options)

                    if !chapterTitle.isEmpty {
                        Text("\(isAudio ? "Đang nghe" : "Đang đọc"): \(chapterTitle)")
                            .font(rowSize.font(.caption2, base: 11))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    /// Dòng gọn (nấc 1–2) thay cho dòng phụ + "Đang đọc": mô tả (kiểu Khám phá) hoặc "tác giả · Ch. N" (kiểu kệ;
    /// video ghi "Tập N", âm thanh "Bài N" như thẻ lưới).
    @ViewBuilder
    private func compactSubtitle(kind: ExtensionContentKind, options: BookDisplayTranslation.Options) -> some View {
        let text = compactSubtitleText(kind: kind, options: options)
        if !text.isEmpty {
            Text(text)
                .font(rowSize.font(.caption2, base: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private func compactSubtitleText(kind: ExtensionContentKind, options: BookDisplayTranslation.Options) -> String {
        if showDescription, !item.description.isEmpty {
            return BookDisplayTranslation.text(item.description.cleanHTML(), options)
        }
        var parts: [String] = []
        if !item.author.isEmpty {
            parts.append(DisplayTextFormatter.titleCase(BookDisplayTranslation.author(item.author, options)))
        }
        if showChapter {
            parts.append(BookListRowSize.progressLabel(kind: kind, chapterIndex: item.currentChapterIndex))
        }
        return parts.joined(separator: " · ")
    }

    /// Tham số tường minh → của item → tra theo thư mục tiện ích (chỉ khi hai nguồn trên rỗng).
    private var coverPackageId: String {
        if !extensionPackageId.isEmpty { return extensionPackageId }
        if !item.coverPackageId.isEmpty { return item.coverPackageId }
        guard !extensionLocalPath.isEmpty else { return "" }
        return ExtensionLibraryRepository.packageId(forLocalPath: extensionLocalPath) ?? ""
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
                .font(rowSize.font(.caption2, base: 11))
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
    var coverHost: String? { host }
    var coverPackageId: String { extensionPackageId }
}

extension ExtensionItemResult: BookDisplayable {
    var bookId: String { link }
    var title: String { name }
    var coverUrl: String { cover }
    var sourceName: String { "" }
    var currentChapterTitle: String { "" }
    var currentChapterIndex: Int { 0 }
    var coverHost: String? { host }
    var coverTag: String { tag }
}
