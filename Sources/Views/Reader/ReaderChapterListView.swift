import SwiftUI
import SwiftData
import Observation

public struct ChapterRowItem: Identifiable, Sendable, Equatable, Hashable {
    public let id: Int // displayPosition (0 ..< totalCount)
    public let index: Int // logical chapter index (0 ..< totalCount)

    public init(id: Int, index: Int) {
        self.id = id
        self.index = index
    }
}

@MainActor
@Observable
public final class ReaderChapterRowState: Identifiable {
    public let id: Int // displayPosition (0 ..< totalCount)
    public let index: Int // logical chapter index (0 ..< totalCount)
    public var title: String
    public var url: String
    public var isCached: Bool
    public var isPlaceholder: Bool

    public init(id: Int, index: Int, title: String = "", url: String = "", isCached: Bool = false, isPlaceholder: Bool = true) {
        self.id = id
        self.index = index
        self.title = title
        self.url = url
        self.isCached = isCached
        self.isPlaceholder = isPlaceholder
    }
}

@MainActor
@Observable
public final class ReaderChapterListStore {
    public private(set) var rows: [ChapterRowItem] = []
    public private(set) var loadedRowStates: [Int: ReaderChapterRowState] = [:]

    public let bookId: String
    private let modelContext: ModelContext?
    private var onlineChapters: [ChapterResult] = []

    public private(set) var totalCount: Int = 0
    public private(set) var isAscending: Bool = true

    private let pageSize = 100
    private var loadedPages: Set<Int> = []
    private var generationID: Int = 0

    public var isLoadingPage = false

    public init(bookId: String, modelContext: ModelContext?, onlineChapters: [ChapterResult], totalCount: Int, isAscending: Bool = true) {
        self.bookId = bookId
        self.modelContext = modelContext
        self.onlineChapters = onlineChapters
        self.totalCount = totalCount
        self.isAscending = isAscending

        setupPlaceholderRows()
    }

    public func setupPlaceholderRows() {
        guard totalCount > 0 else {
            rows = []
            loadedRowStates = [:]
            loadedPages = []
            return
        }

        var newRows: [ChapterRowItem] = []
        newRows.reserveCapacity(totalCount)
        for i in 0..<totalCount {
            let logicIdx = isAscending ? i : (totalCount - 1 - i)
            newRows.append(ChapterRowItem(id: i, index: logicIdx))
        }
        self.rows = newRows
        self.loadedRowStates = [:]
        self.loadedPages = []
    }

    public func updateSortOrder(isAscending: Bool) {
        self.isAscending = isAscending
        setupPlaceholderRows()
    }

    public func updateChapters(totalCount: Int, onlineChapters: [ChapterResult]) {
        self.onlineChapters = onlineChapters
        self.totalCount = totalCount
        setupPlaceholderRows()
    }

    public func loadPageIfNeeded(displayPosition: Int) {
        let page = displayPosition / pageSize
        if loadedPages.contains(page) { return }

        loadPagesAround(page: page)
    }

    public func loadPagesAround(page targetPage: Int) {
        let minPage = max(0, targetPage - 1)
        let maxPage = min((totalCount - 1) / pageSize, targetPage + 1)
        let pagesToLoad = Set(minPage...maxPage)

        // Evict pages outside the window
        let pagesToEvict = loadedPages.subtracting(pagesToLoad)
        for p in pagesToEvict {
            evictPage(p)
        }

        // Dọn dẹp triệt để bất kỳ key nào ngoài cửa sổ 3 trang trong loadedRowStates
        let startBound = minPage * pageSize
        let endBound = (maxPage + 1) * pageSize
        let keysToEvict = loadedRowStates.keys.filter { $0 < startBound || $0 >= endBound }
        for k in keysToEvict {
            loadedRowStates.removeValue(forKey: k)
        }

        let pagesToFetch = pagesToLoad.subtracting(loadedPages)
        guard !pagesToFetch.isEmpty else { return }

        generationID += 1
        let currentGen = generationID

        Task {
            for p in pagesToFetch {
                guard currentGen == self.generationID else { return }
                await fetchPage(p, currentGen: currentGen)
            }
        }
    }

    private func evictPage(_ page: Int) {
        let startIdx = page * pageSize
        let endIdx = min(totalCount, startIdx + pageSize)
        for i in startIdx..<endIdx {
            loadedRowStates.removeValue(forKey: i)
        }
        loadedPages.remove(page)
    }

    private func fetchPage(_ page: Int, currentGen: Int) async {
        let startIdx = page * pageSize
        let endIdx = min(totalCount, startIdx + pageSize)
        guard startIdx < endIdx else { return }

        let logicalIndices = (startIdx..<endIdx).map { i in
            isAscending ? i : (totalCount - 1 - i)
        }

        let minLogicalIndex = logicalIndices.min() ?? 0
        let maxLogicalIndex = logicalIndices.max() ?? 0

        var fetchedData: [Int: (title: String, url: String, isCached: Bool)] = [:]

        if let context = modelContext {
            do {
                var descriptor = FetchDescriptor<Chapter>(
                    predicate: #Predicate<Chapter> { $0.bookId == bookId && $0.index >= minLogicalIndex && $0.index <= maxLogicalIndex }
                )
                descriptor.sortBy = [SortDescriptor(\.index, order: isAscending ? .forward : .reverse)]
                let chapters = try context.fetch(descriptor)
                for chap in chapters {
                    fetchedData[chap.index] = (chap.title, chap.url, chap.isCached)
                }
            } catch {
                AppLogger.shared.log("❌ [ReaderChapterListStore] Lỗi fetch trang mục lục: \(error.localizedDescription)")
            }
        } else {
            for idx in logicalIndices {
                if idx < onlineChapters.count {
                    let chap = onlineChapters[idx]
                    fetchedData[idx] = (chap.name, chap.url, false)
                }
            }
        }

        guard currentGen == self.generationID else { return }

        for i in startIdx..<endIdx {
            let logicIdx = isAscending ? i : (totalCount - 1 - i)
            let state = loadedRowStates[i] ?? {
                let s = ReaderChapterRowState(id: i, index: logicIdx, isPlaceholder: true)
                loadedRowStates[i] = s
                return s
            }()

            if let data = fetchedData[logicIdx] {
                state.title = data.title
                state.url = data.url
                state.isCached = data.isCached
                state.isPlaceholder = false
            } else {
                state.title = "Chương \(logicIdx + 1)"
                state.url = ""
                state.isCached = false
                state.isPlaceholder = false
            }
        }

        loadedPages.insert(page)
    }

    public func rowState(for item: ChapterRowItem) -> ReaderChapterRowState {
        if let state = loadedRowStates[item.id] {
            return state
        }
        let placeholder = ReaderChapterRowState(
            id: item.id,
            index: item.index,
            title: "Đang tải...",
            url: "",
            isCached: false,
            isPlaceholder: true
        )
        loadedRowStates[item.id] = placeholder
        return placeholder
    }

    public func markCached(index: Int) {
        if let position = rows.firstIndex(where: { $0.index == index }) {
            if let state = loadedRowStates[position] {
                state.isCached = true
            }
        }
    }

    public func jumpToChapter(index: Int) async -> Int {
        let displayPosition = isAscending ? index : (totalCount - 1 - index)
        let page = displayPosition / pageSize

        if loadedPages.contains(page) {
            return displayPosition
        }

        isLoadingPage = true
        generationID += 1
        let currentGen = generationID

        await fetchPage(page, currentGen: currentGen)

        loadPagesAround(page: page)

        isLoadingPage = false
        return displayPosition
    }

    public func searchChapters(query: String) -> [ChapterRowItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [ChapterRowItem] = []

        if let context = modelContext {
            do {
                var descriptor = FetchDescriptor<Chapter>(
                    predicate: #Predicate<Chapter> { $0.bookId == bookId && $0.title.contains(trimmed) }
                )
                descriptor.fetchLimit = 100
                descriptor.sortBy = [SortDescriptor(\.index, order: isAscending ? .forward : .reverse)]
                let chapters = try context.fetch(descriptor)

                results = chapters.map { chap in
                    let displayPos = isAscending ? chap.index : (totalCount - 1 - chap.index)
                    let state = ReaderChapterRowState(
                        id: displayPos,
                        index: chap.index,
                        title: chap.title,
                        url: chap.url,
                        isCached: chap.isCached,
                        isPlaceholder: false
                    )
                    loadedRowStates[displayPos] = state
                    return ChapterRowItem(id: displayPos, index: chap.index)
                }
            } catch {
                AppLogger.shared.log("❌ [ReaderChapterListStore] Lỗi tìm kiếm offline: \(error.localizedDescription)")
            }
        } else {
            let matches = onlineChapters.enumerated().filter { _, chapter in
                chapter.name.localizedCaseInsensitiveContains(trimmed)
            }
            let limitedMatches = matches.prefix(100)
            results = limitedMatches.map { index, chapter in
                let displayPos = isAscending ? index : (totalCount - 1 - index)
                let state = ReaderChapterRowState(
                    id: displayPos,
                    index: index,
                    title: chapter.name,
                    url: chapter.url,
                    isCached: false,
                    isPlaceholder: false
                )
                loadedRowStates[displayPos] = state
                return ChapterRowItem(id: displayPos, index: index)
            }
            if !isAscending {
                results.reverse()
            }
        }

        return results
    }

    // Legacy support methods
    public func synchronize(sortedChapters: [Chapter], onlineChapters: [ChapterResult]) {
        let count = !sortedChapters.isEmpty ? sortedChapters.count : onlineChapters.count
        updateChapters(totalCount: count, onlineChapters: onlineChapters)
    }
}

public struct ReaderChapterListView: View {
    public let bookId: String
    public let bookTitle: String?
    public let bookAuthor: String?
    public let bookCoverUrl: String?
    public let bookDetailUrl: String?
    public let localBook: Book?
    public let ext: Extension?
    public let currentChapterIndex: Int
    public let isTranslationEnabled: Bool
    public let theme: ReaderTheme
    public let store: ReaderChapterListStore
    @Binding public var onlineChapters: [ChapterResult]
    public let onSelectChapter: (Int) -> Void
    public let onClose: () -> Void
    public var onDragChanged: ((CGFloat) -> Void)? = nil
    public var onDragEnded: ((CGFloat) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var showingBookDetail = false
    @State private var searchQuery = ""
    @State private var isAscending = true
    @State private var isUpdating = false
    @State private var errorMessage = ""
    @State private var didPositionInitialChapter = false

    private var filteredChapters: [ChapterRowItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return store.rows
        } else {
            return store.searchChapters(query: query)
        }
    }

    private var metadataTitle: String {
        let original = firstNonempty(localBook?.title, bookTitle) ?? "FreeBook"
        guard isTranslationEnabled, TranslateUtils.containsChinese(original) else {
            return original
        }
        return TranslateUtils.translateMeta(original, bookId: bookId)
    }

    private var metadataAuthor: String {
        let original = firstNonempty(localBook?.author, bookAuthor) ?? "Không rõ"
        guard isTranslationEnabled, TranslateUtils.containsChinese(original) else {
            return original
        }
        return TranslateUtils.translateAuthorHanViet(original)
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

                    Text(metadataAuthor)
                        .font(.subheadline)
                        .foregroundColor(theme.textColor.opacity(0.72))
                        .lineLimit(1)

                    HStack(spacing: 0) {
                        Text("\(store.totalCount) chương")
                            .font(.caption.weight(.medium))
                            .foregroundColor(theme.textColor.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer(minLength: 4)

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
            .onChanged { value in
                let v = value.translation.height
                let h = abs(value.translation.width)
                guard v > 0, v >= h else { return }
                onDragChanged?(v)
            }
            .onEnded { value in
                let horizontalDistance = abs(value.translation.width)
                let verticalDistance = value.translation.height
                guard verticalDistance >= 72,
                      verticalDistance >= horizontalDistance * 1.25 else {
                    onDragEnded?(0)
                    return
                }
                onDragEnded?(verticalDistance)
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
                    ForEach(filteredChapters) { item in
                        let chapter = store.rowState(for: item)
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
                            if searchQuery.isEmpty {
                                store.loadPageIfNeeded(displayPosition: item.id)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .background(theme.backgroundColor)
                .scrollContentBackground(.hidden)

                if store.isLoadingPage {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .tint(theme.textColor)
                }
            }
            .onAppear {
                guard !didPositionInitialChapter else { return }
                didPositionInitialChapter = true
                Task {
                    let _ = await store.jumpToChapter(index: currentChapterIndex)
                    DispatchQueue.main.async {
                        proxy.scrollTo(currentChapterIndex, anchor: .center)
                    }
                }
            }
        }
    }

    private func displayTitle(for chapter: ReaderChapterRowState) -> String {
        guard !chapter.isPlaceholder else { return "Đang tải..." }
        guard isTranslationEnabled, TranslateUtils.containsChinese(chapter.title) else {
            return chapter.title
        }
        return TranslateUtils.translateChapterTitle(chapter.title, bookId: bookId)
    }

    private func refreshChapters() {
        guard let ext else {
            errorMessage = "Không tìm thấy tiện ích bóc tách!"
            ToastManager.shared.show(message: errorMessage, type: .error)
            return
        }
        let url = localBook?.detailUrl ?? bookDetailUrl ?? ""
        guard !url.isEmpty else {
            errorMessage = "Đường dẫn truyện không hợp lệ!"
            ToastManager.shared.show(message: errorMessage, type: .error)
            return
        }

        isUpdating = true
        errorMessage = ""
        Task {
            do {
                var allChapters: [ChapterResult] = []
                if ExtensionManager.shared.hasScript(localPath: ext.localPath, scriptKey: "page") {
                    let pages = try await ExtensionManager.shared.page(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        url: url,
                        host: localBook?.host,
                        configJson: ext.configJson
                    )
                    for pageURL in pages {
                        allChapters.append(contentsOf: try await ExtensionManager.shared.toc(
                            localPath: ext.localPath,
                            downloadUrl: ext.downloadUrl,
                            url: pageURL,
                            host: localBook?.host,
                            configJson: ext.configJson
                        ))
                    }
                } else {
                    allChapters = try await ExtensionManager.shared.toc(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        url: url,
                        host: localBook?.host,
                        configJson: ext.configJson
                    )
                }

                if let book = localBook {
                    let existingURLs = Set(book.chapters.map(\.url))
                    let additions = allChapters.enumerated().filter { !existingURLs.contains($0.element.url) }
                    for (index, item) in additions {
                        let chapId = Chapter.generateId(bookId: book.bookId, url: item.url, index: index)
                        let chapter = Chapter(
                            id: chapId,
                            bookId: book.bookId,
                            title: item.name,
                            url: item.url,
                            index: index,
                            host: item.host
                        )
                        chapter.book = book
                        modelContext.insert(chapter)
                        book.chapters.append(chapter)
                    }
                    if (book.host ?? "").isEmpty, let host = allChapters.first?.host, !host.isEmpty {
                        book.host = host
                    }
                    try? modelContext.save()
                    store.updateChapters(totalCount: book.chapters.count, onlineChapters: onlineChapters)
                    ToastManager.shared.show(message: additions.isEmpty ? "Mục lục đã mới nhất" : "Đã thêm \(additions.count) chương mới", type: .success)
                } else {
                    let oldCount = onlineChapters.count
                    onlineChapters = allChapters
                    store.updateChapters(totalCount: allChapters.count, onlineChapters: allChapters)
                    let added = max(0, allChapters.count - oldCount)
                    ToastManager.shared.show(message: added == 0 ? "Mục lục đã mới nhất" : "Đã thêm \(added) chương mới", type: .success)
                }
                isUpdating = false
            } catch {
                errorMessage = "Lỗi cập nhật: \(error.localizedDescription)"
                isUpdating = false
                ToastManager.shared.show(message: errorMessage, type: .error)
            }
        }
    }
}

private struct ReaderChapterRowView: View {
    let chapter: ReaderChapterRowState
    let isCurrent: Bool
    let displayTitle: String
    let theme: ReaderTheme
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(displayTitle)
                    .font(.body)
                    .foregroundColor(isCurrent ? .blue : theme.textColor)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                Spacer()
                if !chapter.isPlaceholder && chapter.isCached {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(chapter.isPlaceholder)
        .listRowBackground(isCurrent ? Color.blue.opacity(0.08) : theme.backgroundColor)
    }
}
