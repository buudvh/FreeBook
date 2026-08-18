import Foundation
import SwiftData

@MainActor
extension ReaderChapterListStore {
    func pageRange(for page: Int) -> Range<Int>? {
        guard page >= 0 && page <= (totalCount - 1) / pageSize else { return nil }
        let startIdx = page * pageSize
        let endIdx = min(totalCount, startIdx + pageSize)
        guard startIdx < endIdx else { return nil }
        return startIdx..<endIdx
    }

    func publishCachedPageIfAvailable(_ page: Int) -> Bool {
        guard page >= 0 && page <= (totalCount - 1) / pageSize else { return false }
        let startIdx = page * pageSize
        let endIdx = min(totalCount, startIdx + pageSize)
        guard startIdx < endIdx else { return false }
        guard let cached = pageCache[page] else { return false }

        let expectedCount = endIdx - startIdx
        guard cached.count == expectedCount else { return false }

        var nextStates = loadedRowStates
        for displayPos in startIdx..<endIdx {
            let logicIdx = isAscending ? displayPos : (totalCount - 1 - displayPos)
            guard let item = cached[logicIdx], !item.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            nextStates[displayPos] = ReaderChapterRowState(
                id: displayPos,
                index: logicIdx,
                title: item.title,
                url: item.url,
                isCached: item.isCached,
                isPlaceholder: false
            )
        }

        loadedRowStates = nextStates
        loadedPages.insert(page)
        return true
    }

    func hasLoadedRows(for page: Int) -> Bool {
        guard let range = pageRange(for: page) else { return false }
        return range.contains { loadedRowStates[$0] != nil }
    }

    func prunePageCache() {
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
                AppLogger.shared.log("❌ [ChapterList] page=\(page) seam fetch error: \(error)")
                fetchedData = nil
            }
        } else if let context = modelContext {
            let localBookId = bookId
            let worker = BackgroundPagingWorker(container: context.container)
            do {
                fetchedData = try await worker.fetchPage(bookId: localBookId, minLogicalIndex: minLogicalIndex, maxLogicalIndex: maxLogicalIndex, isTranslationEnabled: isTranslationEnabled)
            } catch {
                AppLogger.shared.log("❌ [ChapterList] page=\(page) fetch error: \(error)")
                fetchedData = nil
            }
        } else {
            var data: [Int: (title: String, url: String, isCached: Bool)] = [:]
            for idx in logicalIndices {
                if idx < onlineChapters.count {
                    let chap = onlineChapters[idx]
                    let trimmedUrl = chap.url.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedUrl.isEmpty {
                        let displayTitle: String
                        if isTranslationEnabled && TranslateUtils.containsChinese(chap.name) {
                            displayTitle = TranslateUtils.translateChapterTitle(chap.name, bookId: bookId)
                        } else {
                            displayTitle = chap.name
                        }
                        data[idx] = (displayTitle, trimmedUrl, false)
                    }
                }
            }
            fetchedData = data
        }

        let expectedCount = endIdx - startIdx
        if let fetched = fetchedData, fetched.count == expectedCount, fetched.values.allSatisfy({ !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            self.pageCache[page] = fetched
            self.prunePageCache()
            return fetched
        } else {
            self.pageCache.removeValue(forKey: page)
            return nil
        }
    }

    func prefetchPageIfNeeded(page: Int) {
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

    func prefetchAround(displayPosition: Int) {
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

    func scheduleDeferredNeighborPrefetch(around page: Int) {
        let lastPage = max(0, (totalCount - 1) / pageSize)
        let pages = [page - 1, page + 1].filter { $0 >= 0 && $0 <= lastPage }
        scheduleDeferredPrefetch(pages: pages, delayNanoseconds: 300 * 1_000_000)
    }

    func scheduleDeferredPrefetch(pages: [Int], delayNanoseconds: UInt64) {
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
}
