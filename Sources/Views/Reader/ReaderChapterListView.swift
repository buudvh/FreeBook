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

@available(iOS 17.0, *)
public struct SearchChapterDTO: Sendable {
    public let index: Int
    public let title: String
    public let url: String
    public let isCached: Bool

    public init(index: Int, title: String, url: String, isCached: Bool) {
        self.index = index
        self.title = title
        self.url = url
        self.isCached = isCached
    }
}

@available(iOS 17.0, *)
actor BackgroundSearchWorker {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func searchChapters(bookId: String, query: String, isAscending: Bool) -> [SearchChapterDTO] {
        let context = ModelContext(container)
        let localBookId = bookId
        let localQuery = query

        var descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate<Chapter> { $0.bookId == localBookId && $0.title.contains(localQuery) }
        )
        descriptor.fetchLimit = 100
        descriptor.sortBy = [SortDescriptor(\.index, order: isAscending ? .forward : .reverse)]

        do {
            let chapters = try context.fetch(descriptor)
            return chapters.map { chap in
                SearchChapterDTO(
                    index: chap.index,
                    title: chap.title,
                    url: chap.url,
                    isCached: chap.isCached
                )
            }
        } catch {
            AppLogger.shared.log("❌ [BackgroundSearchWorker] Lỗi tìm kiếm: \(error.localizedDescription)")
            return []
        }
    }
}
@available(iOS 17.0, *)
actor BackgroundPagingWorker {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchPage(bookId: String, minLogicalIndex: Int, maxLogicalIndex: Int) throws -> [Int: (title: String, url: String, isCached: Bool)] {
        let context = ModelContext(container)
        let localBookId = bookId
        let localMin = minLogicalIndex
        let localMax = maxLogicalIndex

        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate<Chapter> { $0.bookId == localBookId && $0.index >= localMin && $0.index <= localMax }
        )

        let chapters = try context.fetch(descriptor)
        var data: [Int: (title: String, url: String, isCached: Bool)] = [:]
        for chap in chapters {
            data[chap.index] = (chap.title, chap.url, chap.isCached)
        }
        return data
    }
}

@MainActor
@Observable
public final class ReaderChapterListStore {
    public private(set) var loadedRowStates: [Int: ReaderChapterRowState] = [:]

    public private(set) var searchResults: [ChapterRowItem] = []
    public private(set) var searchResultStates: [Int: ReaderChapterRowState] = [:]
    public private(set) var isSearching = false

    private var searchTask: Task<Void, Never>? = nil
    private var searchTaskID = 0
    private var currentSearchQuery = ""

    public let bookId: String
    private let modelContext: ModelContext?
    private var onlineChapters: [ChapterResult] = []

    public private(set) var totalCount: Int = 0
    public private(set) var isAscending: Bool = true

    public let pageSize = 100
    private var loadedPages: Set<Int> = []
    private var currentTargetPage: Int? = nil
    private var currentGeneration: Int = 0

    // Injected loader seam
    var pageLoaderSeam: (@Sendable (Int) async throws -> [Int: (title: String, url: String, isCached: Bool)]?)? = nil

    var pageCacheCount: Int { pageCache.count }

    // Coordinated window token & request IDs
    private var latestWindowRequestID = UUID()
    private var activeLoadingTargetPage: Int? = nil
    private var pageRequestIDs: [Int: UUID] = [:]
    private var pageCache: [Int: [Int: (title: String, url: String, isCached: Bool)]] = [:]

    private var inFlightPages: [Int: Task<[Int: (title: String, url: String, isCached: Bool)]?, Never>] = [:]
    private var loadTask: Task<Void, Never>? = nil

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
        currentGeneration += 1
        loadTask?.cancel()
        loadTask = nil

        for (_, t) in inFlightPages {
            t.cancel()
        }
        inFlightPages.removeAll()
        pageRequestIDs.removeAll()
        pageCache.removeAll()

        activeLoadingTargetPage = nil
        latestWindowRequestID = UUID()
        currentTargetPage = nil
        isLoadingPage = false

        loadedRowStates = [:]
        loadedPages = []
        searchResults = []
        searchResultStates = [:]
    }

    public func updateSortOrder(isAscending: Bool) {
        self.isAscending = isAscending
        setupPlaceholderRows()

        if !currentSearchQuery.isEmpty {
            performSearch(query: currentSearchQuery)
        }
    }

    public func updateChapters(totalCount: Int, onlineChapters: [ChapterResult]) {
        self.onlineChapters = onlineChapters
        self.totalCount = totalCount
        setupPlaceholderRows()
    }

    public func item(at displayPosition: Int) -> ChapterRowItem? {
        guard displayPosition >= 0 && displayPosition < totalCount else { return nil }
        let logicIdx = isAscending ? displayPosition : (totalCount - 1 - displayPosition)
        return ChapterRowItem(id: displayPosition, index: logicIdx)
    }

    public func loadPageIfNeeded(displayPosition: Int) {
        guard displayPosition >= 0 && displayPosition < totalCount else { return }
        let page = displayPosition / pageSize
        self.currentTargetPage = page

        let minPage = max(0, page - 1)
        let maxPage = min((totalCount - 1) / pageSize, page + 1)
        let pagesToLoad = Set(minPage...maxPage)
        if pagesToLoad.isSubset(of: loadedPages) { return }

        loadPagesAround(page: page)
    }

    public func loadPagesAround(page targetPage: Int) {
        guard targetPage >= 0 && targetPage <= (totalCount - 1) / pageSize else { return }
        if activeLoadingTargetPage == targetPage { return }

        let gen = currentGeneration
        let requestID = UUID()
        self.latestWindowRequestID = requestID
        self.activeLoadingTargetPage = targetPage

        loadTask = Task {
            defer {
                if self.latestWindowRequestID == requestID {
                    self.activeLoadingTargetPage = nil
                }
            }

            let minPage = max(0, targetPage - 1)
            let maxPage = min((totalCount - 1) / pageSize, targetPage + 1)
            let pagesToLoad = Array(minPage...maxPage)

            var pageTasks: [Int: Task<[Int: (title: String, url: String, isCached: Bool)]?, Never>] = [:]
            for p in pagesToLoad {
                if self.loadedPages.contains(p) { continue }
                if let existing = self.inFlightPages[p] {
                    pageTasks[p] = existing
                } else {
                    let reqID = UUID()
                    self.pageRequestIDs[p] = reqID
                    let task = Task {
                        await self.performPageFetch(page: p, requestID: reqID)
                    }
                    self.inFlightPages[p] = task
                    pageTasks[p] = task
                }
            }

            var results: [Int: [Int: (title: String, url: String, isCached: Bool)]] = [:]
            var allSucceeded = true
            for (p, task) in pageTasks {
                if let fetched = await task.value {
                    results[p] = fetched
                } else {
                    allSucceeded = false
                }
            }

            if Task.isCancelled || gen != self.currentGeneration || requestID != self.latestWindowRequestID {
                return
            }

            guard allSucceeded else {
                return
            }

            var nextStates: [Int: ReaderChapterRowState] = [:]
            for p in pagesToLoad {
                let startIdx = p * self.pageSize
                let endIdx = min(self.totalCount, startIdx + self.pageSize)

                if self.loadedPages.contains(p) {
                    for i in startIdx..<endIdx {
                        if let existing = self.loadedRowStates[i] {
                            nextStates[i] = ReaderChapterRowState(
                                id: existing.id,
                                index: existing.index,
                                title: existing.title,
                                url: existing.url,
                                isCached: existing.isCached,
                                isPlaceholder: existing.isPlaceholder
                            )
                        }
                    }
                } else if let fetched = results[p] {
                    for i in startIdx..<endIdx {
                        let logicIdx = self.isAscending ? i : (self.totalCount - 1 - i)
                        if let data = fetched[logicIdx] {
                            nextStates[i] = ReaderChapterRowState(
                                id: i,
                                index: logicIdx,
                                title: data.title,
                                url: data.url,
                                isCached: data.isCached,
                                isPlaceholder: false
                            )
                        } else {
                            nextStates[i] = ReaderChapterRowState(
                                id: i,
                                index: logicIdx,
                                title: "Chương \(logicIdx + 1)",
                                url: "",
                                isCached: false,
                                isPlaceholder: false
                            )
                        }
                    }
                    self.loadedPages.insert(p)
                }
            }

            self.loadedPages = Set(pagesToLoad)
            self.loadedRowStates = nextStates
        }
    }

    private func prunePageCache() {
        guard pageCache.count > 5 else { return }
        let target = currentTargetPage ?? 0
        var furthestPage: Int? = nil
        var maxDistance = -1
        for p in pageCache.keys {
            let dist = abs(p - target)
            if dist > maxDistance {
                maxDistance = dist
                furthestPage = p
            }
        }
        if let pageToRemove = furthestPage {
            pageCache.removeValue(forKey: pageToRemove)
        }
    }

    public func prefetchPageIfNeeded(page: Int) {
        guard page >= 0 && page <= (totalCount - 1) / pageSize else { return }
        guard !loadedPages.contains(page) else { return }
        if pageCache[page] != nil || inFlightPages[page] != nil { return }

        let gen = currentGeneration
        let reqID = UUID()
        self.pageRequestIDs[page] = reqID
        let task: Task<[Int: (title: String, url: String, isCached: Bool)]?, Never> = Task {
            let fetched = await performPageFetch(page: page, requestID: reqID)
            if Task.isCancelled || gen != self.currentGeneration { return nil }
            if let fetched = fetched {
                self.pageCache[page] = fetched
                self.prunePageCache()
            }
            return fetched
        }
        inFlightPages[page] = task
    }

    func performPageFetch(page: Int, requestID: UUID) async -> [Int: (title: String, url: String, isCached: Bool)]? {
        if let cached = pageCache[page] {
            return cached
        }

        defer {
            if self.pageRequestIDs[page] == requestID {
                self.inFlightPages.removeValue(forKey: page)
                self.pageRequestIDs.removeValue(forKey: page)
            }
        }

        let startIdx = page * pageSize
        let endIdx = min(totalCount, startIdx + pageSize)
        guard startIdx < endIdx else { return nil }

        let logicalIndices = (startIdx..<endIdx).map { i in
            isAscending ? i : (totalCount - 1 - i)
        }

        let minLogicalIndex = logicalIndices.min() ?? 0
        let maxLogicalIndex = logicalIndices.max() ?? 0

        var fetchedData: [Int: (title: String, url: String, isCached: Bool)]? = nil

        if let seam = pageLoaderSeam {
            do {
                fetchedData = try await seam(page)
            } catch {
                fetchedData = nil
            }
        } else if let context = modelContext {
            let localBookId = bookId
            let localMin = minLogicalIndex
            let localMax = maxLogicalIndex
            let worker = BackgroundPagingWorker(container: context.container)
            do {
                fetchedData = try await worker.fetchPage(bookId: localBookId, minLogicalIndex: localMin, maxLogicalIndex: localMax)
            } catch {
                AppLogger.shared.log("❌ [BackgroundPagingWorker] Lỗi fetch page: \(error.localizedDescription)")
                fetchedData = nil
            }
        } else {
            var data: [Int: (title: String, url: String, isCached: Bool)] = [:]
            for idx in logicalIndices {
                if idx < onlineChapters.count {
                    let chap = onlineChapters[idx]
                    data[idx] = (chap.name, chap.url, false)
                }
            }
            fetchedData = data
        }

        if let fetched = fetchedData {
            self.pageCache[page] = fetched
            self.prunePageCache()
        }
        return fetchedData
    }

    public func rowState(for item: ChapterRowItem) -> ReaderChapterRowState {
        return rowState(at: item.id)
    }

    public func rowState(at displayPosition: Int) -> ReaderChapterRowState {
        guard displayPosition >= 0 && displayPosition < totalCount else {
            return ReaderChapterRowState(
                id: displayPosition,
                index: displayPosition,
                title: "",
                url: "",
                isCached: false,
                isPlaceholder: true
            )
        }
        if !searchResults.isEmpty {
            if let state = searchResultStates[displayPosition] {
                return state
            }
        }
        if let state = loadedRowStates[displayPosition] {
            return state
        }
        let logicIdx = isAscending ? displayPosition : (totalCount - 1 - displayPosition)
        return ReaderChapterRowState(
            id: displayPosition,
            index: logicIdx,
            title: "Đang tải...",
            url: "",
            isCached: false,
            isPlaceholder: true
        )
    }

    public func markCached(index: Int) {
        guard index >= 0 && index < totalCount else { return }
        let displayPos = isAscending ? index : (totalCount - 1 - index)
        if let state = loadedRowStates[displayPos] {
            state.isCached = true
        }
    }

    public func jumpToChapter(index: Int) async -> Int {
        guard index >= 0 && index < totalCount else { return 0 }
        let displayPosition = isAscending ? index : (totalCount - 1 - index)
        let page = displayPosition / pageSize
        self.currentTargetPage = page

        if loadedPages.contains(page) {
            return displayPosition
        }

        isLoadingPage = true
        loadPagesAround(page: page)
        if let task = loadTask {
            _ = await task.result
        }
        isLoadingPage = false
        return displayPosition
    }

    public func performSearch(query: String) {
        searchTaskID += 1
        let thisTaskID = searchTaskID
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentSearchQuery = trimmed
        guard !trimmed.isEmpty else {
            self.searchResults = []
            self.searchResultStates = [:]
            self.isSearching = false
            return
        }

        self.isSearching = true

        let gen = currentGeneration

        searchTask = Task {
            defer {
                if self.searchTaskID == thisTaskID {
                    self.isSearching = false
                }
            }

            do {
                try await Task.sleep(nanoseconds: 250 * 1_000_000)
            } catch {
                return
            }

            if Task.isCancelled { return }

            var matchedItems: [ChapterRowItem] = []
            var matchedStates: [Int: ReaderChapterRowState] = [:]

            if let context = modelContext {
                let worker = BackgroundSearchWorker(container: context.container)
                let dtos = await worker.searchChapters(bookId: bookId, query: trimmed, isAscending: isAscending)

                if Task.isCancelled { return }

                for chap in dtos {
                    let displayPos = isAscending ? chap.index : (totalCount - 1 - chap.index)
                    let state = ReaderChapterRowState(
                        id: displayPos,
                        index: chap.index,
                        title: chap.title,
                        url: chap.url,
                        isCached: chap.isCached,
                        isPlaceholder: false
                    )
                    matchedStates[displayPos] = state
                    matchedItems.append(ChapterRowItem(id: displayPos, index: chap.index))
                }
            } else {
                var count = 0
                for (index, chapter) in onlineChapters.enumerated() {
                    if count >= 100 { break }
                    if chapter.name.localizedCaseInsensitiveContains(trimmed) {
                        let displayPos = isAscending ? index : (totalCount - 1 - index)
                        let state = ReaderChapterRowState(
                            id: displayPos,
                            index: index,
                            title: chapter.name,
                            url: chapter.url,
                            isCached: false,
                            isPlaceholder: false
                        )
                        matchedStates[displayPos] = state
                        matchedItems.append(ChapterRowItem(id: displayPos, index: index))
                        count += 1
                    }
                }
                if !isAscending {
                    matchedItems.reverse()
                }
            }

            if Task.isCancelled || gen != self.currentGeneration { return }

            self.searchResultStates = matchedStates
            self.searchResults = matchedItems
        }
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
                                    store.loadPageIfNeeded(displayPosition: displayPosition)
                                    let indexInPage = displayPosition % store.pageSize
                                    if indexInPage < 15 && displayPosition >= 15 {
                                        store.prefetchPageIfNeeded(page: (displayPosition - 15) / store.pageSize)
                                    } else if indexInPage > 85 && displayPosition + 15 < store.totalCount {
                                        store.prefetchPageIfNeeded(page: (displayPosition + 15) / store.pageSize)
                                    }
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

                if store.isLoadingPage || store.isSearching {
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
                    let localBookId = book.bookId
                    let descriptor = FetchDescriptor<Chapter>(
                        predicate: #Predicate<Chapter> { $0.bookId == localBookId }
                    )
                    let totalCount = (try? modelContext.fetchCount(descriptor)) ?? 0
                    store.updateChapters(totalCount: totalCount, onlineChapters: onlineChapters)
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
