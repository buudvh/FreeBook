import Foundation
import SwiftData

@available(iOS 17.0, *)
@MainActor
final class ChapterContentProvider {
    private let cache: SharedChapterCache

    init(cache: SharedChapterCache) {
        self.cache = cache
    }

    func cachedOriginalContent(for index: Int) -> String? {
        guard let chapter = cache.get(index), chapter.state == .loaded else { return nil }
        if !chapter.originalContent.isEmpty {
            return chapter.originalContent
        }
        return chapter.content.isEmpty ? nil : chapter.content
    }
}
