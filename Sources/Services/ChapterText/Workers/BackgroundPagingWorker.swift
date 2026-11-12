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
        // Tên hiển thị: dịch ⇒ bản lưu `title_trans` (đã qua phồn → giản của truyện) / dịch sống; tắt dịch ⇒ tên đã chuyển
        // phồn → giản (chạy cả khi tắt dịch, 1.3.846).
        let options = ChineseTextPipeline.Options(
            converts: shouldConvertTraditionalToSimplified, translates: isTranslationEnabled, dictionaryBookId: bookId
        )

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
                let displayTitle = ChineseTextPipeline.chapterTitle(chap.title, storedTranslation: chap.titleTrans, options)
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
                let displayTitle = ChineseTextPipeline.chapterTitle(chap.title, storedTranslation: chap.titleTrans, options)
                map[chap.index] = (displayTitle, trimmedUrl, chap.isCached)
            }
            return map
        }
    }
}
