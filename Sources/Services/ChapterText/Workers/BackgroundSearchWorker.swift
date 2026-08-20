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
            do {
                let storeResults = try await ChapterStore.shared.searchChapters(bookId: bookId, query: query)
                let sorted = isAscending ? storeResults.sorted(by: { $0.index < $1.index }) : storeResults.sorted(by: { $0.index > $1.index })
                return sorted.compactMap { chap in
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
