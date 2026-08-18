import Foundation
import SwiftData
import Observation

struct ChapterRowData: Sendable {
    let title: String
    let url: String
    let isCached: Bool
}

@MainActor
@Observable
public final class ReaderChapterListStore {
    // MARK: - Search state

    public private(set) var searchResults: [ChapterRowItem] = []
    public private(set) var searchResultStates: [Int: ReaderChapterRowState] = [:]
    public private(set) var isSearching = false
    private let searchCoordinator = ChapterListSearchCoordinator()
    private var currentSearchQuery = ""

    // MARK: - Book identity

    public let bookId: String
    internal let modelContext: ModelContext?
    internal var onlineChapters: [ChapterResult]
    public private(set) var totalCount: Int = 0
    public private(set) var isAscending: Bool = true
    public private(set) var isTranslationEnabled: Bool = false

    public let pageSize = 100

    // MARK: - Row state (single source of truth)

    public internal(set) var rows: [Int: ReaderChapterRowState] = [:]

    // MARK: - Load bookkeeping

    var inFlightPages: [Int: Task<[Int: ChapterRowData]?, Never>] = [:]
    var currentGeneration: Int = 0
    var retryTask: Task<Void, Never>? = nil
    var lastRequestedPage: Int? = nil

    var pageLoaderSeam: (@Sendable (Int) async throws -> [Int: ChapterRowData]?)? = nil

    public init(
        bookId: String,
        modelContext: ModelContext?,
        onlineChapters: [ChapterResult],
        totalCount: Int,
        isAscending: Bool = true,
        isTranslationEnabled: Bool = false
    ) {
        self.bookId = bookId
        self.modelContext = modelContext
        self.onlineChapters = onlineChapters
        self.totalCount = totalCount
        self.isAscending = isAscending
        self.isTranslationEnabled = isTranslationEnabled
    }

    // MARK: - Reset

    private func reset() {
        currentGeneration += 1
        for (_, task) in inFlightPages {
            task.cancel()
        }
        inFlightPages.removeAll()
        retryTask?.cancel()
        retryTask = nil
        rows = [:]
        searchCoordinator.cancel()
        searchResults = []
        searchResultStates = []
    }

    // MARK: - Updates

    public func updateTranslation(isTranslationEnabled: Bool) {
        guard self.isTranslationEnabled != isTranslationEnabled else { return }
        self.isTranslationEnabled = isTranslationEnabled
        reset()
        reloadViewport()
    }

    public func updateSortOrder(isAscending: Bool) {
        guard self.isAscending != isAscending else { return }
        self.isAscending = isAscending
        reset()
        reloadViewport()
        if !currentSearchQuery.isEmpty {
            performSearch(query: currentSearchQuery)
        }
    }

    public func updateChapters(totalCount: Int, onlineChapters: [ChapterResult]) {
        guard totalCount != self.totalCount || onlineChapters != self.onlineChapters else { return }
        self.onlineChapters = onlineChapters
        self.totalCount = totalCount
        reset()
        reloadViewport()
    }

    private func reloadViewport() {
        guard let page = lastRequestedPage,
              totalCount > 0,
              page >= 0,
              page <= (totalCount - 1) / pageSize else { return }
        loadPagesAround(page: page, includeNeighbors: true)
    }

    // MARK: - Row access

    public func item(at displayPosition: Int) -> ChapterRowItem? {
        guard displayPosition >= 0 && displayPosition < totalCount else { return nil }
        let logicIdx = isAscending ? displayPosition : (totalCount - 1 - displayPosition)
        return ChapterRowItem(id: displayPosition, index: logicIdx)
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
        if !searchResults.isEmpty, let state = searchResultStates[displayPosition] {
            return state
        }
        if let state = rows[displayPosition] {
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
        if let state = rows[displayPos] {
            state.isCached = true
        }
    }

    // MARK: - Loading

    public func loadPageIfNeeded(displayPosition: Int) {
        guard displayPosition >= 0 && displayPosition < totalCount else { return }
        let page = displayPosition / pageSize
        let lastPage = max(0, (totalCount - 1) / pageSize)
        let window = Array(max(0, page - 1)...min(lastPage, page + 1))
        loadPagesAround(pages: window, targetPage: page)
    }

    public func loadVisiblePageIfNeeded(displayPosition: Int) {
        guard displayPosition >= 0 && displayPosition < totalCount else { return }
        let page = displayPosition / pageSize
        if isPageLoaded(page) { return }
        loadPagesAround(pages: [page], targetPage: page)
    }

    public func prefetchAround(displayPosition: Int) {
        guard displayPosition >= 0 && displayPosition < totalCount else { return }
        let page = displayPosition / pageSize
        let lastPage = max(0, (totalCount - 1) / pageSize)
        let neighbors = [page - 1, page + 1].filter { $0 >= 0 && $0 <= lastPage && !isPageLoaded($0) }
        guard !neighbors.isEmpty else { return }
        loadPagesAround(pages: neighbors, targetPage: page)
    }

    public func loadPagesAround(page targetPage: Int, includeNeighbors: Bool = true) {
        let lastPage = max(0, (totalCount - 1) / pageSize)
        guard targetPage >= 0 && targetPage <= lastPage else { return }
        let minPage = includeNeighbors ? max(0, targetPage - 1) : targetPage
        let maxPage = includeNeighbors ? min(lastPage, targetPage + 1) : targetPage
        loadPagesAround(pages: Array(minPage...maxPage), targetPage: targetPage)
    }

    private func loadPagesAround(pages: [Int], targetPage: Int) {
        guard totalCount > 0 else { return }
        self.lastRequestedPage = targetPage
        let gen = currentGeneration
        let validPages = pages.filter { $0 >= 0 && $0 <= (totalCount - 1) / pageSize && !isPageLoaded($0) }
        guard !validPages.isEmpty else { return }

        var tasks: [(Int, Task<[Int: ChapterRowData]?, Never>)] = []
        for p in validPages {
            if let existing = inFlightPages[p] {
                tasks.append((p, existing))
            } else {
                let task = Task { [weak self] in
                    guard let self else { return nil }
                    defer {
                        if gen == self.currentGeneration {
                            self.inFlightPages.removeValue(forKey: p)
                        }
                    }
                    guard let data = await self.fetchPageData(page: p) else { return nil }
                    guard gen == self.currentGeneration, !Task.isCancelled else { return nil }
                    self.publish(page: p, data: data)
                    return data
                }
                inFlightPages[p] = task
                tasks.append((p, task))
            }
        }

        let watcher = Task { [weak self] in
            guard let self else { return }
            var failedPages: [Int] = []
            for (p, task) in tasks {
                if await task.value == nil {
                    failedPages.append(p)
                }
            }
            guard gen == self.currentGeneration, !Task.isCancelled, !failedPages.isEmpty else { return }
            self.scheduleRetry(pages: failedPages)
        }
    }

    public func jumpToChapter(index: Int) async -> Int {
        guard index >= 0 && index < totalCount else { return 0 }
        let displayPosition = isAscending ? index : (totalCount - 1 - index)
        let page = displayPosition / pageSize

        if !isPageLoaded(page) {
            loadPagesAround(pages: [page], targetPage: page)
            if let task = inFlightPages[page] {
                _ = await task.value
            }
        }
        return displayPosition
    }

    // MARK: - Data source

    private func fetchPageData(page: Int) async -> [Int: ChapterRowData]? {
        let startIdx = page * pageSize
        let endIdx = min(totalCount, startIdx + pageSize)
        guard startIdx < endIdx else { return nil }
        let logicalIndices = (startIdx..<endIdx).map { i in
            isAscending ? i : (totalCount - 1 - i)
        }

        var data: [Int: ChapterRowData]? = nil

        if let seam = pageLoaderSeam {
            do {
                data = try await seam(page)
            } catch {
                AppLogger.shared.log("❌ [ChapterList] page=\(page) seam fetch error: \(error)")
                data = nil
            }
        } else if let context = modelContext {
            let localBookId = bookId
            let worker = BackgroundPagingWorker(container: context.container)
            do {
                let fetched = try await worker.fetchPage(
                    bookId: localBookId,
                    minLogicalIndex: logicalIndices.min() ?? 0,
                    maxLogicalIndex: logicalIndices.max() ?? 0,
                    isTranslationEnabled: isTranslationEnabled
                )
                data = fetched.mapValues { ChapterRowData(title: $0.title, url: $0.url, isCached: $0.isCached) }
            } catch {
                AppLogger.shared.log("❌ [ChapterList] page=\(page) fetch error: \(error)")
                data = nil
            }
        } else {
            var map: [Int: ChapterRowData] = [:]
            for idx in logicalIndices {
                guard idx < onlineChapters.count else { continue }
                let chap = onlineChapters[idx]
                let trimmedUrl = chap.url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedUrl.isEmpty else { continue }
                let displayTitle: String
                if isTranslationEnabled && TranslateUtils.containsChinese(chap.name) {
                    displayTitle = TranslateUtils.translateChapterTitle(chap.name, bookId: bookId)
                } else {
                    displayTitle = chap.name
                }
                map[idx] = ChapterRowData(title: displayTitle, url: trimmedUrl, isCached: false)
            }
            data = map
        }

        guard let data,
              data.count == (endIdx - startIdx),
              data.values.allSatisfy({ !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return nil
        }
        return data
    }

    private func publish(page: Int, data: [Int: ChapterRowData]) {
        let startIdx = page * pageSize
        let endIdx = min(totalCount, startIdx + pageSize)
        guard startIdx < endIdx else { return }
        var next = rows
        for i in startIdx..<endIdx {
            let logicIdx = isAscending ? i : (totalCount - 1 - i)
            if let d = data[logicIdx] {
                next[i] = ReaderChapterRowState(
                    id: i,
                    index: logicIdx,
                    title: d.title,
                    url: d.url,
                    isCached: d.isCached,
                    isPlaceholder: false
                )
            }
        }
        rows = next
    }

    private func isPageLoaded(_ page: Int) -> Bool {
        let startIdx = page * pageSize
        let endIdx = min(totalCount, startIdx + pageSize)
        guard startIdx < endIdx else { return true }
        for i in startIdx..<endIdx {
            if rows[i] == nil { return false }
        }
        return true
    }

    private func scheduleRetry(pages: [Int]) {
        let gen = currentGeneration
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, gen == self.currentGeneration else { return }
            for p in pages {
                self.loadPagesAround(page: p, includeNeighbors: false)
            }
        }
    }

    // MARK: - Search

    public func performSearch(query: String) {
        self.currentSearchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchCoordinator.performSearch(
            query: currentSearchQuery,
            bookId: bookId,
            totalCount: totalCount,
            isAscending: isAscending,
            isTranslationEnabled: isTranslationEnabled,
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