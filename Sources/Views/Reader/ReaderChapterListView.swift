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
        self.theme = theme
        self.store = store
        self._onlineChapters = onlineChapters
        self.isLocalTXTBook = isLocalTXTBook
        self.onSelectChapter = onSelectChapter
        self.onClose = onClose
        self.onLocalTOCRefreshed = onLocalTOCRefreshed
    }

    @Environment(\.modelContext) private var modelContext
    @State private var showingBookDetail = false
    @State private var searchQuery = ""
    @State private var isAscending = true
    @State internal var isUpdating = false
    @State internal var errorMessage = ""
    @State private var isPositioningInitialChapter = true
    @State private var displayTitleCache: [Int: String] = [:]
    @State private var deferredVisiblePageTask: Task<Void, Never>? = nil

    private var metadataTitle: String {
        let original = firstNonempty(localBook?.title, bookTitle) ?? "FreeBook"
        let translated = isTranslationEnabled && TranslateUtils.containsChinese(original)
            ? TranslateUtils.translateMeta(original, bookId: bookId)
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
                .fullScreenCover(isPresented: $showingBookDetail) {
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

                    if let sourceName = ext?.name ?? localBook?.sourceName, !sourceName.isEmpty {
                        Text(sourceName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(4)
                    }

                    HStack(spacing: 0) {
                        Text("\(store.totalCount) chương")
                            .font(.caption.weight(.medium))
                            .foregroundColor(theme.textColor.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

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

    private var chapterList: some View {
        ScrollViewReader { proxy in
            ZStack {
                List {
                    if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ForEach(0..<store.totalCount, id: \.self) { displayPosition in
                            if let item = store.item(at: displayPosition) {
                                let chapter = store.rowState(at: displayPosition)
                                ReaderChapterRowView(
                                    chapter: chapter,
                                    isCurrent: item.index == currentChapterIndex,
                                    displayTitle: displayTitle(for: chapter),
                                    theme: theme,
                                    onSelect: {
                                        onSelectChapter(item.index)
                                        onClose()
                                    }
                                )
                                .id(item.index)
                                .onAppear {
                                    guard !isPositioningInitialChapter else {
                                        return
                                    }
                                    scheduleVisiblePageWork(displayPosition: displayPosition)
                                }
                            }
                        }
                    } else {
                        ForEach(store.searchResults) { item in
                            let chapter = store.rowState(at: item.id)
                            ReaderChapterRowView(
                                chapter: chapter,
                                isCurrent: item.index == currentChapterIndex,
                                displayTitle: displayTitle(for: chapter),
                                theme: theme,
                                onSelect: {
                                    onSelectChapter(item.index)
                                    onClose()
                                }
                            )
                            .id(item.index)
                        }
                    }
                }
                .listStyle(.plain)
                .background(theme.backgroundColor)
                .scrollContentBackground(.hidden)

                if store.isSearching {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .tint(theme.textColor)
                }
            }
            .onChange(of: searchQuery) { _, newValue in
                store.performSearch(query: newValue)
            }
            .onAppear {
                scrollToCurrentChapter(proxy: proxy)
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    scrollToCurrentChapter(proxy: proxy)
                }
            }
            .onChange(of: currentChapterIndex) { _, _ in
                if isPresented {
                    scrollToCurrentChapter(proxy: proxy)
                }
            }
            .onChange(of: isTranslationEnabled) { _, newValue in
                displayTitleCache.removeAll()
                store.updateTranslation(isTranslationEnabled: newValue)
            }
        }
    }

    private func displayTitle(for chapter: ReaderChapterRowState) -> String {
        guard !chapter.isPlaceholder else { return "Đang tải..." }
        if !isTranslationEnabled {
            return chapter.title
        }
        if let cached = displayTitleCache[chapter.index] {
            return cached
        }
        if TranslateUtils.containsChinese(chapter.title) {
            let translated = TranslateUtils.translateChapterTitle(chapter.title, bookId: bookId)
            displayTitleCache[chapter.index] = translated
            return translated
        }
        return chapter.title
    }

    private func scrollToCurrentChapter(proxy: ScrollViewProxy) {
        guard isPresented else { return }
        Task {
            let displayPosition = await store.jumpToChapter(index: currentChapterIndex)
            if let item = store.item(at: displayPosition) {
                proxy.scrollTo(item.index, anchor: .center)
            }
            warmNearbyTitles(aroundDisplayPosition: displayPosition, windowSize: 8)
            isPositioningInitialChapter = false
        }
    }

    private func scheduleVisiblePageWork(displayPosition: Int) {
        deferredVisiblePageTask?.cancel()
        deferredVisiblePageTask = Task {
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                store.loadVisiblePageIfNeeded(displayPosition: displayPosition)
                store.prefetchAround(displayPosition: displayPosition)
            }
        }
    }

    private func warmNearbyTitles(aroundDisplayPosition targetDisplayPosition: Int, windowSize: Int = 8) {
        guard isTranslationEnabled else { return }
        let total = store.totalCount
        guard total > 0 else { return }

        let minPos = max(0, targetDisplayPosition - windowSize)
        let maxPos = min(total - 1, targetDisplayPosition + windowSize)

        var toWarm: [(index: Int, rawTitle: String)] = []
        for pos in minPos...maxPos {
            if let rowState = store.loadedRowStates[pos], !rowState.isPlaceholder, !rowState.title.isEmpty {
                let logicalIndex = rowState.index
                guard displayTitleCache[logicalIndex] == nil else { continue }
                if TranslateUtils.containsChinese(rowState.title) {
                    toWarm.append((index: logicalIndex, rawTitle: rowState.title))
                }
            }
        }

        guard !toWarm.isEmpty else { return }
        let currentBookId = bookId
        Task.detached(priority: .utility) { [toWarm, currentBookId] in
            var results: [Int: String] = [:]
            for item in toWarm {
                let translated = TranslateUtils.translateChapterTitle(item.rawTitle, bookId: currentBookId)
                results[item.index] = translated
            }
            let finalResults = results
            await MainActor.run {
                self.displayTitleCache.merge(finalResults) { current, _ in current }
            }
        }
    }
}


