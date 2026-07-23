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
    private let repository: ChapterRepositoryProtocol

    init(repository: ChapterRepositoryProtocol) {
        self.repository = repository
    }

    func searchChapters(bookId: String, query: String, isAscending: Bool, isTranslationEnabled: Bool) async -> [SearchChapterDTO] {
        let localBookId = bookId
        let localQuery = query

        do {
            var chapters = try await repository.searchChapters(bookId: localBookId, query: localQuery)
            if !isAscending {
                chapters.reverse()
            }
            return chapters.map { chap in
                let displayTitle: String
                if isTranslationEnabled {
                    if let trans = chap.titleTrans, !trans.isEmpty {
                        displayTitle = trans
                    } else if TranslateUtils.containsChinese(chap.title) {
                        displayTitle = TranslateUtils.translateChapterTitle(chap.title, bookId: localBookId)
                    } else {
                        displayTitle = chap.title
                    }
                } else {
                    displayTitle = chap.title
                }
                return SearchChapterDTO(
                    index: chap.index,
                    title: displayTitle,
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
    private let repository: ChapterRepositoryProtocol

    init(repository: ChapterRepositoryProtocol) {
        self.repository = repository
    }

    func fetchPage(bookId: String, minLogicalIndex: Int, maxLogicalIndex: Int, isTranslationEnabled: Bool) async throws -> [Int: (title: String, url: String, isCached: Bool)] {
        let count = maxLogicalIndex - minLogicalIndex + 1
        let chapters = try await repository.loadPageKeyset(bookId: bookId, startIdx: minLogicalIndex, limit: count)
        var data: [Int: (title: String, url: String, isCached: Bool)] = [:]
        for chap in chapters {
            let displayTitle: String
            if isTranslationEnabled {
                if let trans = chap.titleTrans, !trans.isEmpty {
                    displayTitle = trans
                } else if TranslateUtils.containsChinese(chap.title) {
                    displayTitle = TranslateUtils.translateChapterTitle(chap.title, bookId: bookId)
                } else {
                    displayTitle = chap.title
                }
            } else {
                displayTitle = chap.title
            }
            data[chap.index] = (displayTitle, chap.url, chap.isCached)
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
    private let chapterRepository: ChapterRepositoryProtocol
    private var onlineChapters: [ChapterResult] = []

    public private(set) var totalCount: Int = 0
    public private(set) var isAscending: Bool = true
    public private(set) var isTranslationEnabled: Bool = false

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
    private var deferredPrefetchTask: Task<Void, Never>? = nil

    public var isLoadingPage = false

    public init(bookId: String, modelContext: ModelContext?, onlineChapters: [ChapterResult], totalCount: Int, isAscending: Bool = true, isTranslationEnabled: Bool = false, chapterRepository: any ChapterRepositoryProtocol) {
        self.bookId = bookId
        self.modelContext = modelContext
        self.onlineChapters = onlineChapters
        self.totalCount = totalCount
        self.isAscending = isAscending
        self.isTranslationEnabled = isTranslationEnabled
        self.chapterRepository = chapterRepository

        setupPlaceholderRows()
    }

    public func updateTranslation(isTranslationEnabled: Bool) {
        guard self.isTranslationEnabled != isTranslationEnabled else { return }
        self.isTranslationEnabled = isTranslationEnabled
        setupPlaceholderRows()
    }

    public func setupPlaceholderRows() {
        currentGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        deferredPrefetchTask?.cancel()
        deferredPrefetchTask = nil

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

    public func loadVisiblePageIfNeeded(displayPosition: Int) {
        guard displayPosition >= 0 && displayPosition < totalCount else { return }
        let page = displayPosition / pageSize
        self.currentTargetPage = page

        if loadedPages.contains(page), hasLoadedRows(for: page) {
            return
        }
        if publishCachedPageIfAvailable(page) {
            return
        }
        loadPagesAround(page: page, includeNeighbors: false)
    }

    public func loadPagesAround(page targetPage: Int, includeNeighbors: Bool = true) {
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

            let minPage = includeNeighbors ? max(0, targetPage - 1) : targetPage
            let maxPage = includeNeighbors ? min((totalCount - 1) / pageSize, targetPage + 1) : targetPage
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
                        } else if logicIdx >= 0 && logicIdx < onlineChapters.count {
                            let chap = onlineChapters[logicIdx]
                            let displayTitle: String
                            if isTranslationEnabled && TranslateUtils.containsChinese(chap.name) {
                                displayTitle = TranslateUtils.translateChapterTitle(chap.name, bookId: bookId)
                            } else {
                                displayTitle = chap.name
                            }
                            nextStates[i] = ReaderChapterRowState(
                                id: i,
                                index: logicIdx,
                                title: displayTitle,
                                url: chap.url,
                                isCached: false,
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

    private func pageRange(for page: Int) -> Range<Int>? {
        guard page >= 0 && page <= (totalCount - 1) / pageSize else { return nil }
        let startIdx = page * pageSize
        let endIdx = min(totalCount, startIdx + pageSize)
        guard startIdx < endIdx else { return nil }
        return startIdx..<endIdx
    }

    private func hasLoadedRows(for page: Int) -> Bool {
        guard let range = pageRange(for: page) else { return false }
        return range.contains { loadedRowStates[$0] != nil }
    }

    @discardableResult
    private func publishCachedPageIfAvailable(_ page: Int) -> Bool {
        guard let fetched = pageCache[page], let range = pageRange(for: page) else {
            return false
        }

        for i in range {
            let logicIdx = isAscending ? i : (totalCount - 1 - i)
            if let data = fetched[logicIdx] {
                loadedRowStates[i] = ReaderChapterRowState(
                    id: i,
                    index: logicIdx,
                    title: data.title,
                    url: data.url,
                    isCached: data.isCached,
                    isPlaceholder: false
                )
            } else if logicIdx >= 0 && logicIdx < onlineChapters.count {
                let chap = onlineChapters[logicIdx]
                let displayTitle: String
                if isTranslationEnabled && TranslateUtils.containsChinese(chap.name) {
                    displayTitle = TranslateUtils.translateChapterTitle(chap.name, bookId: bookId)
                } else {
                    displayTitle = chap.name
                }
                loadedRowStates[i] = ReaderChapterRowState(
                    id: i,
                    index: logicIdx,
                    title: displayTitle,
                    url: chap.url,
                    isCached: false,
                    isPlaceholder: false
                )
            } else {
                loadedRowStates[i] = ReaderChapterRowState(
                    id: i,
                    index: logicIdx,
                    title: "Chương \(logicIdx + 1)",
                    url: "",
                    isCached: false,
                    isPlaceholder: false
                )
            }
        }
        loadedPages.insert(page)
        return true
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

    public func prefetchAround(displayPosition: Int) {
        guard displayPosition >= 0 && displayPosition < totalCount else { return }
        let indexInPage = displayPosition % pageSize
        let page: Int?
        if indexInPage < 15 && displayPosition >= 15 {
            page = (displayPosition - 15) / pageSize
        } else if indexInPage > 85 && displayPosition + 15 < totalCount {
            page = (displayPosition + 15) / pageSize
        } else {
            page = nil
        }

        guard let page else { return }
        scheduleDeferredPrefetch(pages: [page], delayNanoseconds: 180 * 1_000_000)
    }

    private func scheduleDeferredNeighborPrefetch(around page: Int) {
        let lastPage = max(0, (totalCount - 1) / pageSize)
        let pages = [page - 1, page + 1].filter { $0 >= 0 && $0 <= lastPage }
        scheduleDeferredPrefetch(pages: pages, delayNanoseconds: 300 * 1_000_000)
    }

    private func scheduleDeferredPrefetch(pages: [Int], delayNanoseconds: UInt64) {
        let validPages = pages.filter { page in
            page >= 0 &&
            page <= (totalCount - 1) / pageSize &&
            !loadedPages.contains(page) &&
            pageCache[page] == nil &&
            inFlightPages[page] == nil
        }
        guard !validPages.isEmpty else { return }

        deferredPrefetchTask?.cancel()
        let gen = currentGeneration
        deferredPrefetchTask = Task(priority: .utility) {
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled, gen == self.currentGeneration else { return }
            for page in validPages {
                self.prefetchPageIfNeeded(page: page)
            }
        }
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
        } else {
            let localBookId = bookId
            let localMin = minLogicalIndex
            let localMax = maxLogicalIndex
            let transEnabled = isTranslationEnabled
            let worker = BackgroundPagingWorker(repository: chapterRepository)
            var dataFromStore: [Int: (title: String, url: String, isCached: Bool)] = [:]
            do {
                dataFromStore = try await worker.fetchPage(bookId: localBookId, minLogicalIndex: localMin, maxLogicalIndex: localMax, isTranslationEnabled: transEnabled)
            } catch {
                AppLogger.shared.log("❌ [BackgroundPagingWorker] Lỗi fetch page: \(error.localizedDescription)")
            }

            for idx in logicalIndices {
                if dataFromStore[idx] == nil && idx >= 0 && idx < onlineChapters.count {
                    let chap = onlineChapters[idx]
                    let displayTitle: String
                    if isTranslationEnabled && TranslateUtils.containsChinese(chap.name) {
                        displayTitle = TranslateUtils.translateChapterTitle(chap.name, bookId: bookId)
                    } else {
                        displayTitle = chap.name
                    }
                    dataFromStore[idx] = (displayTitle, chap.url, false)
                }
            }
            fetchedData = dataFromStore
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
        let page = displayPosition / pageSize
        if let cached = pageCache[page], let data = cached[logicIdx] {
            return ReaderChapterRowState(
                id: displayPosition,
                index: logicIdx,
                title: data.title,
                url: data.url,
                isCached: data.isCached,
                isPlaceholder: false
            )
        }
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

        loadPagesAround(page: page, includeNeighbors: false)
        if let task = loadTask {
            _ = await task.result
        }
        scheduleDeferredNeighborPrefetch(around: page)
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

            let worker = BackgroundSearchWorker(repository: chapterRepository)
            let dtos = await worker.searchChapters(bookId: bookId, query: trimmed, isAscending: isAscending, isTranslationEnabled: isTranslationEnabled)

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

            if Task.isCancelled || gen != self.currentGeneration { return }

            self.searchResultStates = matchedStates
            self.searchResults = matchedItems
        }
    }
}

public struct ReaderChapterListView: View {
    @Environment(\.chapterRepository) private var chapterRepository
    @Environment(\.modelContext) private var modelContext
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
    public let onSelectChapter: (Int) -> Void
    public let onClose: () -> Void

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
        onSelectChapter: @escaping (Int) -> Void,
        onClose: @escaping () -> Void
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
        self.onSelectChapter = onSelectChapter
        self.onClose = onClose
    }

    @State private var showingBookDetail = false
    @State private var searchQuery = ""
    @State private var isAscending = true
    @State private var isUpdating = false
    @State private var errorMessage = ""
    @State private var isPositioningInitialChapter = true
    @State private var displayTitleCache: [Int: String] = [:]
    @State private var deferredVisiblePageTask: Task<Void, Never>? = nil
    @State private var refreshTask: Task<Void, Never>? = nil

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
        .onDisappear {
            refreshTask?.cancel()
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
        
        // ✅ Debounce để tránh scroll nhiều lần khi view xuất hiện
        Task { @MainActor in
            // Delay nhỏ để đảm bảo view đã render hoàn toàn
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            let displayPosition = await store.jumpToChapter(index: currentChapterIndex)
            if let item = store.item(at: displayPosition) {
                proxy.scrollTo(item.index, anchor: .center)
            }
            
            // ✅ Warm titles với delay để không block animation
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
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
        
        // ✅ Giới hạn chỉ warm tối đa 20 titles để tránh block main thread
        let limitedWarm = Array(toWarm.prefix(20))
        let currentBookId = bookId
        Task.detached(priority: .utility) {
            var results: [Int: String] = [:]
            for item in limitedWarm {
                let translated = TranslateUtils.translateChapterTitle(item.rawTitle, bookId: currentBookId)
                results[item.index] = translated
            }
            await MainActor.run { [results] in
                self.displayTitleCache.merge(results) { current, _ in current }
            }
        }
    }

    private func isValidChapterUrl(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "#" { return false }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("javascript:") || lower.hasPrefix("about:blank") { return false }
        return true
    }

    private func makeSafeChapterId(
        bookId: String,
        url: String,
        index: Int,
        seenIds: inout Set<String>
    ) -> String {
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateId: String
        if !isValidChapterUrl(trimmedUrl) {
            candidateId = "\(bookId.count):\(bookId)|I:\(index)"
        } else {
            candidateId = Chapter.generateId(bookId: bookId, url: trimmedUrl, index: index)
        }

        if seenIds.contains(candidateId) {
            let fallbackId = "\(bookId.count):\(bookId)|I:\(index)"
            seenIds.insert(fallbackId)
            return fallbackId
        } else {
            seenIds.insert(candidateId)
            return candidateId
        }
    }

    @discardableResult
    private func appendNewChaptersOnly(for book: Book, pageResults: [ChapterResult], baseIndex: Int) -> Int {
        let chapterHost = book.host ?? ext?.sourceUrl
        let targetBookId = book.bookId
        var addedModels: [ChapterModel] = []

        for (offset, item) in pageResults.enumerated() {
            let absoluteIndex = baseIndex + offset
            let effectiveHost = !item.host.isEmpty ? item.host : chapterHost
            let model = ChapterModel(
                bookId: targetBookId,
                index: absoluteIndex,
                title: item.name,
                url: item.url,
                host: effectiveHost
            )
            addedModels.append(model)
        }

        if !addedModels.isEmpty {
            Task {
                try? await chapterRepository.bulkUpsert(bookId: targetBookId, chapters: addedModels)
            }
        }
        return addedModels.count
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

        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = ""

        refreshTask?.cancel()
        refreshTask = Task {
            defer { isUpdating = false }
            do {
                var pages: [String] = []
                var firstPageChaps: [ChapterResult] = []

                if ExtensionManager.shared.hasScript(localPath: ext.localPath, scriptKey: "page") {
                    pages = try await ExtensionManager.shared.page(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        url: url,
                        host: localBook?.host,
                        configJson: ext.configJson
                    )
                    let firstPageUrl = pages.first ?? url
                    firstPageChaps = try await ExtensionManager.shared.toc(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        url: firstPageUrl,
                        host: localBook?.host,
                        configJson: ext.configJson
                    )
                } else {
                    firstPageChaps = try await ExtensionManager.shared.toc(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        url: url,
                        host: localBook?.host,
                        configJson: ext.configJson
                    )
                }

                if Task.isCancelled { return }

                var baseIndex = 0
                var totalNewAdded = 0

                if let book = localBook {
                    let added = appendNewChaptersOnly(for: book, pageResults: firstPageChaps, baseIndex: baseIndex)
                    totalNewAdded += added
                    baseIndex += firstPageChaps.count

                    try? modelContext.save()
                    let targetBookId = book.bookId
                    let currentTotal = (try? await chapterRepository.getTotalChaptersCount(bookId: targetBookId)) ?? 0
                    store.updateChapters(totalCount: currentTotal, onlineChapters: onlineChapters)
                    NotificationCenter.default.post(name: .bookChaptersUpdated, object: nil, userInfo: ["bookId": book.bookId])
                } else {
                    onlineChapters = firstPageChaps
                    baseIndex += firstPageChaps.count
                    store.updateChapters(totalCount: onlineChapters.count, onlineChapters: onlineChapters)
                }

                if pages.count > 1 {
                    let remainingPages = Array(pages.dropFirst())
                    var pendingBatchCount = 0

                    for pageUrl in remainingPages {
                        if Task.isCancelled { break }

                        let pageChaps = try await ExtensionManager.shared.toc(
                            localPath: ext.localPath,
                            downloadUrl: ext.downloadUrl,
                            url: pageUrl,
                            host: localBook?.host,
                            configJson: ext.configJson
                        )
                        if Task.isCancelled { break }

                        if let book = localBook {
                            let added = appendNewChaptersOnly(for: book, pageResults: pageChaps, baseIndex: baseIndex)
                            totalNewAdded += added
                            baseIndex += pageChaps.count
                        } else {
                            onlineChapters.append(contentsOf: pageChaps)
                            baseIndex += pageChaps.count
                        }

                        pendingBatchCount += 1
                        let isLast = (pageUrl == remainingPages.last)

                        if pendingBatchCount >= 10 || isLast {
                            if let book = localBook {
                                try? modelContext.save()
                                let targetBookId = book.bookId
                                let currentTotal = (try? await chapterRepository.getTotalChaptersCount(bookId: targetBookId)) ?? 0
                                store.updateChapters(totalCount: currentTotal, onlineChapters: onlineChapters)
                                NotificationCenter.default.post(name: .bookChaptersUpdated, object: nil, userInfo: ["bookId": book.bookId])
                            } else {
                                store.updateChapters(totalCount: onlineChapters.count, onlineChapters: onlineChapters)
                            }
                            pendingBatchCount = 0
                            await Task.yield()
                        }
                    }
                }

                if !Task.isCancelled {
                    let msg = (localBook != nil)
                        ? (totalNewAdded == 0 ? "Mục lục đã mới nhất" : "Đã thêm \(totalNewAdded) chương mới")
                        : "Đã cập nhật mục lục"
                    ToastManager.shared.show(message: msg, type: .success)
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = "Lỗi cập nhật: \(error.localizedDescription)"
                    ToastManager.shared.show(message: errorMessage, type: .error)
                }
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
