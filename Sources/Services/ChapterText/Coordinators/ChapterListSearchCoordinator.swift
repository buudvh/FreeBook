import Foundation
#if canImport(SwiftData)
import SwiftData
#endif

@MainActor
public final class ChapterListSearchCoordinator {
    private var searchTaskID: Int = 0
    private var searchTask: Task<Void, Never>?

    public init() {}

    deinit {
        searchTask?.cancel()
    }

    public func cancel() {
        searchTask?.cancel()
        searchTask = nil
    }

    public func performSearch(
        query: String,
        bookId: String,
        totalCount: Int,
        isAscending: Bool,
        isTranslationEnabled: Bool,
        shouldConvertTraditionalToSimplified: Bool = false,
        onlineChapters: [ChapterResult],
        modelContainerProvider: (() -> Any?)?,
        onSearchStateChanged: @escaping (Bool) -> Void,
        onResultsReady: @escaping ([ChapterRowItem], [Int: ReaderChapterRowState]) -> Void
    ) {
        searchTaskID += 1
        let thisTaskID = searchTaskID
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onResultsReady([], [:])
            onSearchStateChanged(false)
            return
        }

        onSearchStateChanged(true)

        searchTask = Task {
            defer {
                if self.searchTaskID == thisTaskID {
                    onSearchStateChanged(false)
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

            #if canImport(SwiftData)
            if #available(iOS 17.0, *), let container = modelContainerProvider?() as? SwiftData.ModelContainer {
                let worker = BackgroundSearchWorker(container: container)
                let dtos = await worker.searchChapters(
                    bookId: bookId,
                    query: trimmed,
                    isAscending: isAscending,
                    isTranslationEnabled: isTranslationEnabled,
                    shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
                )

                if Task.isCancelled { return }

                for chap in dtos {
                    let trimmedUrl = chap.url.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedUrl.isEmpty else { continue }
                    let displayPos = isAscending ? chap.index : (totalCount - 1 - chap.index)
                    let state = ReaderChapterRowState(
                        id: displayPos,
                        index: chap.index,
                        title: chap.title,
                        url: trimmedUrl,
                        isCached: chap.isCached,
                        isPlaceholder: false
                    )
                    matchedStates[displayPos] = state
                    matchedItems.append(ChapterRowItem(id: displayPos, index: chap.index))
                }
            } else {
                var count = 0
                // Khớp cả tên đã chuyển phồn → giản (rẻ, có memo); tên hiển thị của dòng khớp như trang mục lục
                // (`ReaderChapterListPageFetcher`: phồn → giản cả khi tắt dịch, dịch sống khi bật — 1.3.846).
                let options = ChineseTextPipeline.Options(
                    converts: shouldConvertTraditionalToSimplified, translates: isTranslationEnabled, dictionaryBookId: bookId
                )
                for (index, chapter) in onlineChapters.enumerated() {
                    if count >= 100 { break }
                    let trimmedUrl = chapter.url.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedUrl.isEmpty else { continue }
                    let convertedName = ChineseTextPipeline.convert(chapter.name, converts: options.converts)
                    if ChapterTitleSearchMatcher.matches(trimmed, anyOf: [convertedName, chapter.name]) {
                        let displayPos = isAscending ? index : (totalCount - 1 - index)
                        let state = ReaderChapterRowState(
                            id: displayPos,
                            index: index,
                            title: ChineseTextPipeline.chapterTitle(convertedName, options.alreadyConverted),
                            url: trimmedUrl,
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
            #endif

            if Task.isCancelled { return }

            onResultsReady(matchedItems, matchedStates)
        }
    }
}
