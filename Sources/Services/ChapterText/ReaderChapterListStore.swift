import Foundation
import SwiftData
import Observation



@MainActor
@Observable
public final class ReaderChapterListStore {
    public internal(set) var loadedRowStates: [Int: ReaderChapterRowState] = [:]

    public private(set) var searchResults: [ChapterRowItem] = []
    public private(set) var searchResultStates: [Int: ReaderChapterRowState] = [:]
    public private(set) var isSearching = false

    private let searchCoordinator = ChapterListSearchCoordinator()
    private var currentSearchQuery = ""

    public let bookId: String
    internal let modelContext: ModelContext?
    internal var onlineChapters: [ChapterResult] = []

    public private(set) var totalCount: Int = 0
    public private(set) var isAscending: Bool = true
    public private(set) var isTranslationEnabled: Bool = false
    public private(set) var shouldConvertTraditionalToSimplified: Bool = false

    public let pageSize = 100
    var loadedPages: Set<Int> = []
    var currentTargetPage: Int? = nil
    private var lastViewportPage: Int? = nil
    var currentGeneration: Int = 0

    var pageLoaderSeam: (@Sendable (Int) async throws -> [Int: (title: String, url: String, isCached: Bool)]?)? = nil
    var pageCacheCount: Int { pageCache.count }

    var latestWindowRequestID = UUID()
    var activeLoadingTargetPage: Int? = nil
    var pageRequestIDs: [Int: UUID] = [:]
    var pageCache: [Int: [Int: (title: String, url: String, isCached: Bool)]] = [:]

    var inFlightPages: [Int: Task<[Int: (title: String, url: String, isCached: Bool)]?, Never>] = [:]
    var loadTask: Task<Void, Never>? = nil
    var deferredPrefetchTask: Task<Void, Never>? = nil

    public var isLoadingPage = false

    public init(bookId: String, modelContext: ModelContext?, onlineChapters: [ChapterResult], totalCount: Int, isAscending: Bool = true, isTranslationEnabled: Bool = false, shouldConvertTraditionalToSimplified: Bool = false) {
        self.bookId = bookId
        self.modelContext = modelContext
        self.onlineChapters = onlineChapters
        self.totalCount = totalCount
        self.isAscending = isAscending
        self.isTranslationEnabled = isTranslationEnabled
        self.shouldConvertTraditionalToSimplified = shouldConvertTraditionalToSimplified

        setupPlaceholderRows()
    }

    public func updateTranslation(
        isTranslationEnabled: Bool,
        shouldConvertTraditionalToSimplified: Bool = false
    ) {
        guard self.isTranslationEnabled != isTranslationEnabled ||
            self.shouldConvertTraditionalToSimplified != shouldConvertTraditionalToSimplified else { return }
        self.isTranslationEnabled = isTranslationEnabled
        self.shouldConvertTraditionalToSimplified = shouldConvertTraditionalToSimplified
        setupPlaceholderRows()
    }

    public func setupPlaceholderRows() {
        currentGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        deferredPrefetchTask?.cancel()
        deferredPrefetchTask = nil
        searchCoordinator.cancel()

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
        reloadViewportAfterReset()
    }

    private func reloadViewportAfterReset() {
        guard let page = lastViewportPage,
              page >= 0,
              page <= (totalCount - 1) / pageSize else { return }
        currentTargetPage = page
        loadPagesAround(page: page, includeNeighbors: true)
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
        self.lastViewportPage = page

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
        self.lastViewportPage = page

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

            guard allSucceeded else { return }

            var nextStates: [Int: ReaderChapterRowState] = loadedRowStates
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
                } else if let fetched = results[p], fetched.count == (endIdx - startIdx) {
                    var pageValid = true
                    for i in startIdx..<endIdx {
                        let logicIdx = self.isAscending ? i : (self.totalCount - 1 - i)
                        if let data = fetched[logicIdx], !data.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            nextStates[i] = ReaderChapterRowState(
                                id: i,
                                index: logicIdx,
                                title: data.title,
                                url: data.url,
                                isCached: data.isCached,
                                isPlaceholder: false
                            )
                        } else {
                            pageValid = false
                            nextStates[i] = ReaderChapterRowState(
                                id: i,
                                index: logicIdx,
                                title: "Chương \(logicIdx + 1)",
                                url: "",
                                isCached: false,
                                isPlaceholder: true
                            )
                        }
                    }
                    if pageValid {
                        self.loadedPages.insert(p)
                    }
                }
            }

            self.loadedRowStates = nextStates
        }
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
        self.lastViewportPage = page

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
        self.currentSearchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchCoordinator.performSearch(
            query: currentSearchQuery,
            bookId: bookId,
            totalCount: totalCount,
            isAscending: isAscending,
            isTranslationEnabled: isTranslationEnabled,
            shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified,
            onlineChapters: onlineChapters,
            modelContainerProvider: { [weak self] in self?.modelContext?.container },
            onSearchStateChanged: { [weak self] isSearching in
                self?.isSearching = isSearching
            },
            onResultsReady: { [weak self] items, states in
                self?.searchResults = items
                self?.searchResultStates = states
            }
        )
    }
}
