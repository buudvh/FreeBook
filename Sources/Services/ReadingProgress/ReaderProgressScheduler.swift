import Foundation

@MainActor
public final class ReaderProgressScheduler {
    public static let shared = ReaderProgressScheduler()

    private init() {}

    public func shouldScheduleProgressSave(bookId: String, chapterIndex: Int, progressToken: Int) -> Bool {
        guard !bookId.isEmpty, chapterIndex >= 0, progressToken > 0 else { return false }
        return true
    }

    public func scheduleSave(
        bookId: String,
        chapterIndex: Int,
        page: Int,
        progressStore: ReadingProgressStore
    ) {
        Task {
            await progressStore.scheduleSave(bookId: bookId, chapterIndex: chapterIndex, page: page)
        }
    }
}
