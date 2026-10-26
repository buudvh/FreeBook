import SwiftUI
import SwiftData

public struct ReaderChapterListView: View {
    public let bookId: String
    public let bookTitle: String?
    public let bookAuthor: String?
    public let bookCoverUrl: String?
    public let bookDetailUrl: String?
    public let localBook: Book?
    public let ext: Extension?
    public let currentChapterIndex: Int
    public let isPresented: Bool
    public let isTranslationEnabled: Bool
    public let shouldConvertTraditionalToSimplified: Bool
    public let theme: ReaderTheme
    public let store: ReaderChapterListStore
    @Binding public var onlineChapters: [ChapterResult]
    public let isLocalTXTBook: Bool
    public let onSelectChapter: (Int) -> Void
    public let onClose: () -> Void
    public let onLocalTOCRefreshed: ((LocalTOCRefreshResult) -> Void)?

    public init(
        bookId: String,
        bookTitle: String?,
        bookAuthor: String?,
        bookCoverUrl: String?,
        bookDetailUrl: String?,
        localBook: Book?,
        ext: Extension?,
        currentChapterIndex: Int,
        isPresented: Bool = true,
        isTranslationEnabled: Bool,
        shouldConvertTraditionalToSimplified: Bool = false,
        theme: ReaderTheme,
        store: ReaderChapterListStore,
        onlineChapters: Binding<[ChapterResult]>,
        isLocalTXTBook: Bool = false,
        onSelectChapter: @escaping (Int) -> Void,
        onClose: @escaping () -> Void,
        onLocalTOCRefreshed: ((LocalTOCRefreshResult) -> Void)? = nil
    ) {
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.bookCoverUrl = bookCoverUrl
        self.bookDetailUrl = bookDetailUrl
        self.localBook = localBook
        self.ext = ext
        self.currentChapterIndex = currentChapterIndex
        self.isPresented = isPresented
        self.isTranslationEnabled = isTranslationEnabled
        self.shouldConvertTraditionalToSimplified = shouldConvertTraditionalToSimplified
        self.theme = theme
        self.store = store
        self._onlineChapters = onlineChapters
        self.isLocalTXTBook = isLocalTXTBook
        self.onSelectChapter = onSelectChapter
        self.onClose = onClose
        self.onLocalTOCRefreshed = onLocalTOCRefreshed
        // Danh sách là sheet dựng lại mỗi lần mở, còn store sống suốt phiên Reader: ô tìm lấy lại truy vấn đang áp.
        self._searchQuery = State(initialValue: store.activeSearchQuery)
    }

    @Environment(\.modelContext) internal var modelContext
    @State private var showingBookDetail = false
    @State internal var searchQuery = ""
    @State internal var isUpdating = false
    @State internal var errorMessage = ""
    @State internal var isPositioningInitialChapter = true
    @State internal var displayTitleCache: [Int: String] = [:]
    @State internal var deferredVisiblePageTask: Task<Void, Never>? = nil
    /// Index **logic** của các chương đang tải lẻ — xem `ReaderChapterListView+Download.swift`.
    @State internal var downloadingChapterIndices: Set<Int> = []
    /// Mở `TaskOptionsSheet` của tác vụ **tải cả truyện** (cùng sheet với nhấn-giữ ở Kệ/Lịch sử).
    @State internal var showingDownloadOptions = false
    /// Luồng nút kệ — xem `ReaderChapterListView+Shelf.swift`.
    @State internal var isConfirmingShelfRemoval = false
    @State internal var collectionPickerBook: Book? = nil

    internal var metadataTitle: String {
        let original = firstNonempty(localBook?.title, bookTitle) ?? "FreeBook"
        let translated = isTranslationEnabled && TranslateUtils.containsChinese(original)
            ? TranslateUtils.translateMeta(
                original,
                bookId: bookId,
                shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
            )
            : original
        return DisplayTextFormatter.titleCase(translated)
    }

    private var metadataAuthor: String {
        guard let original = firstNonempty(localBook?.author, bookAuthor) else {
            return ""
        }
        let translated = isTranslationEnabled && TranslateUtils.containsChinese(original)
            ? TranslateUtils.translateAuthorHanViet(original)
            : original
        return DisplayTextFormatter.titleCase(translated)
    }

    private var metadataCoverUrl: String {
        firstNonempty(localBook?.coverUrl, bookCoverUrl) ?? ""
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider().background(theme.textColor.opacity(0.1))

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Divider().background(theme.textColor.opacity(0.1))
                }

                searchField
                chapterList
            }
            .background(theme.backgroundColor.ignoresSafeArea())
        }
        .accessibilityAction(.escape) {
            onClose()
        }
        .sheet(isPresented: $showingDownloadOptions) {
            if let book = localBook {
                TaskOptionsSheet(book: book, taskType: .download)
            }
        }
        .shelfToggleFlow(
            book: localBook,
            displayTitle: metadataTitle,
            isConfirmingRemoval: $isConfirmingShelfRemoval,
            collectionPickerBook: $collectionPickerBook
        )
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("chapterTitlesDidRetranslate"))) { notification in
            guard let notifBookId = notification.userInfo?["bookId"] as? String, notifBookId == bookId else { return }
            displayTitleCache.removeAll()
            store.reloadAllPages()
        }
    }

    private static let coverWidth: CGFloat = 86
    private static let coverHeight: CGFloat = 120

    /// Thanh kéo là của sheet hệ thống (`ReaderView.readerChapterListSheet`) — header không tự vẽ capsule hay bắt cử
    /// chỉ kéo nữa. Số chương nằm trên dải đáy bìa (`CoverCaptionStrip`, cùng kiểu chỉ bìa của Kệ); hàng nút dồn phải,
    /// sát đáy bìa.
    private var header: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: { showingBookDetail = true }) {
                    BookCoverView(
                        bookId: bookId,
                        coverUrl: metadataCoverUrl,
                        width: Self.coverWidth,
                        height: Self.coverHeight,
                        host: localBook?.host,
                        extensionPackageId: ext?.packageId ?? localBook?.extensionPackageId ?? ""
                    )
                    .overlay(alignment: .bottom) {
                        CoverCaptionStrip(
                            subtitle: "\(store.totalCount) chương",
                            fadeHeight: CoverCaptionStrip.compactFadeHeight
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(bookDetailUrl == nil || ext == nil)
                .sheet(isPresented: $showingBookDetail) {
                    if let detailUrl = bookDetailUrl, let ext {
                        NavigationStack {
                            BookDetailView(
                                bookId: bookId,
                                extensionPackageId: ext.packageId,
                                initialDetailUrl: detailUrl,
                                sourceName: ext.name
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(metadataTitle)
                        .font(.headline)
                        .foregroundColor(theme.textColor)
                        .lineLimit(2)

                    if !metadataAuthor.isEmpty {
                        Text(metadataAuthor)
                            .font(.subheadline)
                            .foregroundColor(theme.textColor.opacity(0.72))
                            .lineLimit(1)
                    }

                    if isLocalTXTBook {
                        HStack(spacing: 4) {
                            Image(systemName: "puzzlepiece.extension")
                                .resizable()
                                .frame(width: 12, height: 12)
                                .foregroundColor(.secondary)
                            Text("Local")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    } else if let ext, !ext.name.isEmpty {
                        HStack(spacing: 4) {
                            ExtensionIconView(localPath: ext.localPath, iconUrl: ext.iconUrl ?? "", size: 14)
                            Text(ext.name)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Spacer(minLength: 0)

                        HStack(spacing: 4) {
                            shelfToggleButton

                            bulkDownloadButton

                            Button(action: retranslateChaptersAction) {
                                Image(systemName: "character.bubble")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                            }
                            .accessibilityLabel("Dịch lại chương và mục lục")

                            if !isLocalTXTBook {
                                if isUpdating {
                                    ProgressView()
                                        .tint(theme.textColor)
                                        .frame(width: 32, height: 32)
                                        .accessibilityLabel("Đang cập nhật mục lục")
                                } else {
                                    Button(action: refreshChapters) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(theme.textColor)
                                            .frame(width: 32, height: 32)
                                    }
                                    .accessibilityLabel("Cập nhật mục lục")
                                }
                            }

                            // Thứ tự đọc thẳng từ store (sống suốt phiên Reader), không giữ bản sao trong view.
                            Button(action: {
                                store.updateSortOrder(isAscending: !store.isAscending)
                            }) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(theme.textColor)
                                    .frame(width: 32, height: 32)
                            }
                            .accessibilityLabel(store.isAscending ? "Sắp xếp chương giảm dần" : "Sắp xếp chương tăng dần")
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Self.coverHeight, alignment: .topLeading)
            }
            // Cột chữ có `Spacer` dọc (đẩy hàng nút xuống đáy bìa): không cố định chiều cao thì header tham chiều cao
            // và chia đôi khoảng trống với `List` bên dưới.
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        // Chừa chỗ cho thanh kéo của sheet hệ thống.
        .padding(.top, 20)
        .padding(.bottom, 10)
        .background(theme.backgroundColor)
    }

    private func firstNonempty(_ primary: String?, _ fallback: String?) -> String? {
        for value in [primary, fallback] {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(theme.textColor.opacity(0.6))
            TextField("Tìm kiếm chương...", text: $searchQuery)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .foregroundColor(theme.textColor)
                .submitLabel(.search)
            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(theme.textColor.opacity(0.6))
                }
            }
        }
        .padding(10)
        .background(theme.textColor.opacity(0.08))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func retranslateChaptersAction() {
        displayTitleCache.removeAll()
        if let book = localBook {
            BookActionRunner.retranslateChapterTitles(for: book)
        }
        store.updateTranslation(
            isTranslationEnabled: isTranslationEnabled,
            shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
        )
        NotificationCenter.default.post(
            name: .translationDictionariesDidUpdate,
            object: nil,
            userInfo: ["bookId": bookId, "scope": DictionaryInvalidationScope.globalReload]
        )
    }
}
