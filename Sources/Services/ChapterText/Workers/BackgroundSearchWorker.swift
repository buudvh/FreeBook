import Foundation
import SwiftData

@available(iOS 17.0, *)
public actor BackgroundSearchWorker {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public func searchChapters(
        bookId: String,
        query: String,
        isAscending: Bool,
        isTranslationEnabled: Bool,
        shouldConvertTraditionalToSimplified: Bool = false
    ) async -> [SearchChapterDTO] {
        if !ChapterStoreConfiguration.enableSwiftDataTOCWrite {
            // Lọc trong Swift trên **tên đang hiển thị** (cùng cách chọn với `BackgroundPagingWorker`) + tên gốc +
            // `titleTrans` — không dùng SQL `LIKE` nữa, xem `ChapterTitleSearchMatcher` (1.3.510).
            do {
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                let toc = try await ChapterStore.shared.fetchOrderedTOC(bookId: bookId)
                var matched: [SearchChapterDTO] = []
                for (offset, chap) in toc.enumerated() {
                    // Mỗi phím gõ huỷ lượt cũ: dừng sớm thay vì dịch nốt cả mục lục.
                    if offset % 200 == 0, Task.isCancelled { return [] }
                    let trimmedUrl = chap.url.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedUrl.isEmpty else { continue }
                    let displayTitle: String
                    if isTranslationEnabled {
                        if !shouldConvertTraditionalToSimplified, let trans = chap.titleTrans, !trans.isEmpty {
                            displayTitle = trans
                        } else if TranslateUtils.containsChinese(chap.title) {
                            displayTitle = TranslateUtils.translateChapterTitle(
                                chap.title,
                                bookId: bookId,
                                shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
                            )
                        } else {
                            displayTitle = chap.title
                        }
                    } else {
                        displayTitle = chap.title
                    }
                    guard ChapterTitleSearchMatcher.matches(trimmed, anyOf: [displayTitle, chap.title, chap.titleTrans]) else {
                        continue
                    }
                    matched.append(SearchChapterDTO(
                        index: chap.index,
                        title: displayTitle,
                        url: trimmedUrl,
                        isCached: chap.isCached
                    ))
                }
                return isAscending ? matched : Array(matched.reversed())
            } catch {
                let bookHash = String(Chapter.hashUrl(bookId).prefix(8))
                AppLogger.shared.log("❌ [BackgroundSearch] bookIdHash=\(bookHash) status=search_failed")
                return []
            }
        } else {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Chapter>(
                predicate: #Predicate<Chapter> { $0.book?.bookId == bookId },
                sortBy: [SortDescriptor(\.index, order: isAscending ? .forward : .reverse)]
            )
            guard let chapters = try? context.fetch(descriptor) else { return [] }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

            return chapters.compactMap { chap in
                guard chap.title.localizedCaseInsensitiveContains(trimmed) || (chap.titleTrans?.localizedCaseInsensitiveContains(trimmed) == true) else { return nil }
                let trimmedUrl = chap.url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedUrl.isEmpty else { return nil }
                let displayTitle: String
                if isTranslationEnabled {
                    if !shouldConvertTraditionalToSimplified, let trans = chap.titleTrans, !trans.isEmpty {
                        displayTitle = trans
                    } else if TranslateUtils.containsChinese(chap.title) {
                        displayTitle = TranslateUtils.translateChapterTitle(
                            chap.title,
                            bookId: bookId,
                            shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
                        )
                    } else {
                        displayTitle = chap.title
                    }
                } else {
                    displayTitle = chap.title
                }
                return SearchChapterDTO(
                    index: chap.index,
                    title: displayTitle,
                    url: trimmedUrl,
                    isCached: chap.isCached
                )
            }
        }
    }
}
