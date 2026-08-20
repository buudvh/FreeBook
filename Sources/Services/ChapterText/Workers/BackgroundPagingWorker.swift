import Foundation
import SwiftData

@available(iOS 17.0, *)
public actor BackgroundPagingWorker {
    public enum BackgroundPagingError: Error {
        case incompletePage
    }

    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public func fetchPage(
        bookId: String,
        minLogicalIndex: Int,
        maxLogicalIndex: Int,
        isTranslationEnabled: Bool,
        shouldConvertTraditionalToSimplified: Bool = false
    ) async throws -> [Int: (title: String, url: String, isCached: Bool)] {
        let count = maxLogicalIndex - minLogicalIndex + 1
        guard count > 0 else { return [:] }

        if !ChapterStoreConfiguration.enableSwiftDataTOCWrite {
            let storeChaps = try await ChapterStore.shared.fetchRange(bookId: bookId, startIndex: minLogicalIndex, count: count)
            let returnedIndices = Set(storeChaps.map { $0.index })
            let expectedIndices = Set(minLogicalIndex...maxLogicalIndex)
            guard returnedIndices == expectedIndices && storeChaps.count == count else {
                throw BackgroundPagingError.incompletePage
            }
            var map: [Int: (title: String, url: String, isCached: Bool)] = [:]
            for chap in storeChaps {
                let trimmedUrl = chap.url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedUrl.isEmpty else {
                    throw BackgroundPagingError.incompletePage
                }
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
                map[chap.index] = (displayTitle, trimmedUrl, chap.isCached)
            }
            return map
        } else {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<Chapter>(
                predicate: #Predicate<Chapter> { $0.book?.bookId == bookId && $0.index >= minLogicalIndex && $0.index <= maxLogicalIndex }
            )
            descriptor.sortBy = [SortDescriptor(\.index, order: .forward)]
            guard let chapters = try? context.fetch(descriptor), chapters.count == count else {
                throw BackgroundPagingError.incompletePage
            }

            var map: [Int: (title: String, url: String, isCached: Bool)] = [:]
            for chap in chapters {
                let trimmedUrl = chap.url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedUrl.isEmpty else {
                    throw BackgroundPagingError.incompletePage
                }
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
                map[chap.index] = (displayTitle, trimmedUrl, chap.isCached)
            }
            return map
        }
    }
}
