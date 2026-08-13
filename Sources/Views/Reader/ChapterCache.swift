import SwiftUI
import Observation

struct ReadingProgress {
    let chapterIndex: Int
    let paragraphIndex: Int

    func isSameLocation(as other: ReadingProgress) -> Bool {
        return self.chapterIndex == other.chapterIndex && self.paragraphIndex == other.paragraphIndex
    }
}

public struct ReadingContext: Hashable, Sendable {
    public let bookId: String
    public let chapterIndex: Int
    public let paragraphIndex: Int
    public let characterOffset: Int?
    public let paragraphProgress: Double?

    public init(
        bookId: String,
        chapterIndex: Int,
        paragraphIndex: Int,
        characterOffset: Int? = nil,
        paragraphProgress: Double? = nil
    ) {
        self.bookId = bookId
        self.chapterIndex = chapterIndex
        self.paragraphIndex = paragraphIndex
        self.characterOffset = characterOffset
        self.paragraphProgress = paragraphProgress
    }
}

public enum ChapterLoadState: Equatable {
    case notLoaded
    case placeholder
    case prefetching
    case loading
    case loaded
    case failed(message: String)
}

extension ChapterLoadState {
    public var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

@available(iOS 17.0, *)
@Observable
public class CachedChapter: Identifiable {
    public let index: Int
    public var state: ChapterLoadState = .placeholder
    public var title: String = ""
    public var content: String = ""
    public var originalTitle: String = ""
    public var originalContent: String = ""
    public var scrollParagraphIndex: Int = -1
    public var paragraphItems: [ParagraphItem] = []
    public var isPositionRestored: Bool = false
    public var revision: Int = 0
    public var isTranslationEnabled: Bool = false
    public var translationToken: Int = 0

    public init(index: Int) {
        self.index = index
    }
}

@available(iOS 17.0, *)
@Observable
public class ChapterCache {
    public var cache: [Int: CachedChapter] = [:]
    @ObservationIgnored private var releaseTasks: [Int: Task<Void, Never>] = [:]

    public init() {}

    public func get(_ index: Int) -> CachedChapter? {
        if let item = cache[index] {
            // Hủy task giải phóng bộ nhớ nếu người dùng quay lại đọc chương này
            releaseTasks[index]?.cancel()
            releaseTasks.removeValue(forKey: index)
            return item
        }
        return nil
    }

    func setPlaceholder(_ index: Int) -> CachedChapter {
        if let item = cache[index] {
            return item
        }
        let newItem = CachedChapter(index: index)
        cache[index] = newItem
        return newItem
    }

    func set(_ index: Int, state: ChapterLoadState) {
        if let item = cache[index] {
            item.state = state
        } else {
            let newItem = CachedChapter(index: index)
            newItem.state = state
            cache[index] = newItem
        }
    }

    func remove(_ index: Int) {
        releaseTasks[index]?.cancel()
        releaseTasks.removeValue(forKey: index)
        cache.removeValue(forKey: index)
    }

    func setScrollParagraph(_ index: Int, paragraphIndex: Int) {
        if let item = cache[index] {
            item.scrollParagraphIndex = paragraphIndex
        }
    }

    // Giải phóng bộ nhớ trễ an toàn bằng Task.sleep
    func queueRelease(_ index: Int, delaySeconds: UInt64 = 10) {
        releaseTasks[index]?.cancel()

        let task = Task {
            do {
                try await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self.performRelease(index)
            } catch {
                // Task bị hủy khi người dùng quay lại đọc chương đó trước thời hạn
            }
        }
        releaseTasks[index] = task
    }

    private func performRelease(_ index: Int) {
        cache.removeValue(forKey: index)
        releaseTasks.removeValue(forKey: index)
        #if DEBUG
        AppLogger.shared.log("🧹 [ChapterCache] Đã giải phóng bộ nhớ chương \(index)")
        #endif
    }

    func clearAll() {
        for task in releaseTasks.values { task.cancel() }
        releaseTasks.removeAll()
        cache.removeAll()
    }

    // Đồng nhất cơ chế giải phóng: Chỉ đưa các chương ngoài cửa sổ vào hàng đợi queueRelease
    func queueReleaseAllNonVisible(keepIndexes: Set<Int>) {
        let keysToRelease = cache.keys.filter { !keepIndexes.contains($0) }
        for key in keysToRelease {
            queueRelease(key, delaySeconds: 5) // Đưa vào hàng đợi xóa sau 5 giây
        }
    }

    // Giải phóng khẩn cấp lập tức (khi nhận Memory Warning)
    func releaseAllNonVisible(keepIndexes: Set<Int>) {
        let keysToRemove = cache.keys.filter { !keepIndexes.contains($0) }
        for key in keysToRemove {
            cache.removeValue(forKey: key)
            releaseTasks[key]?.cancel()
            releaseTasks.removeValue(forKey: key)
        }
    }
}
