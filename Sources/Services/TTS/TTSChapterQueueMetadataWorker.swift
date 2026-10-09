import Foundation
import SwiftData

@available(iOS 17.0, *)
actor TTSChapterQueueMetadataWorker {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchLocalQueue(bookId: String) async -> [TTSChapterInfo] {
        if let storeChaps = try? await ChapterStore.shared.fetchOrderedTOC(bookId: bookId), !storeChaps.isEmpty {
            return storeChaps.map {
                TTSChapterInfo(title: $0.title, url: $0.url, index: $0.index, host: $0.host)
            }
        }
        return []
    }
}
