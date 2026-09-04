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
    }

    @Environment(\.modelContext) internal var modelContext
    @State private var showingBookDetail = false
    @State internal var searchQuery = ""
    @State private var isAscending = true
    @State internal var isUpdating = false
    @State internal var errorMessage = ""
    @State internal var isPositioningInitialChapter = true
    @State internal var displayTitleCache: [Int: String] = [:]
    @State internal var deferredVisiblePageTask: Task<Void, Never>? = nil
    /// Index **logic** của các chương đang tải lẻ — xem `ReaderChapterListView+Download.swift`.
    @State internal var downloadingChapterIndices: Set<Int> = []

    private var metadataTitle: String {
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
    }

    private var header: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(theme.textColor.opacity(0.3))
                .frame(width: 36, height: 5)
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 12) {
                Button(action: { showingBookDetail = true }) {
                    BookCoverView(
                        bookId: bookId,
                        coverUrl: metadataCoverUrl,
                        width: 72,
                        height: 100
                    )
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

                    HStack(spacing: 6) {
                        Text("\(store.totalCount) chương")
                            .font(.caption.weight(.medium))
                            .foregroundColor(theme.textColor.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

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

                        Spacer(minLength: 4)

                        if !isLocalTXTBook {
                            if isUpdating {
                                ProgressView()
                                    .tint(theme.textColor)
                                    .frame(width: 44, height: 44)
                                    .accessibilityLabel("Đang cập nhật mục lục")
                            } else {
                                Button(action: refreshChapters) {
                                    Image(systemName: "arrow.clockwise")
                                        .foregroundColor(theme.textColor)
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Cập nhật mục lục")
                            }
                        }

                        Button(action: {
                            isAscending.toggle()
                            store.updateSortOrder(isAscending: isAscending)
                        }) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.body.weight(.semibold))
                                .foregroundColor(theme.textColor)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(isAscending ? "Sắp xếp chương giảm dần" : "Sắp xếp chương tăng dần")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(theme.backgroundColor)
        .contentShape(Rectangle())
        .simultaneousGesture(dismissGesture)
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                let horizontalDistance = abs(value.translation.width)
                let verticalDistance = value.translation.height
                if verticalDistance >= 72,
                   verticalDistance >= horizontalDistance * 1.25 {
                    onClose()
                }
            }
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
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundColor(theme.textColor)
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
}
