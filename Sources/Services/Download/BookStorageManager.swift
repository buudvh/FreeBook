import Foundation
import SwiftData
import UIKit

@MainActor
public final class BookStorageManager {
    public static let shared = BookStorageManager()

    // Mock seams for unit tests
    public static var mockFetchError: Error? = nil
    public static var mockSaveError: Error? = nil

    private init() {}

    // Xóa sách khỏi kệ
    public func removeFromShelf(_ book: Book, context: ModelContext) throws {
        if book.isHistory {
            book.isOnShelf = false
            try context.save()
        } else {
            try deleteBookComplete(book, context: context)
        }
    }

    // Xóa sách khỏi lịch sử
    public func removeFromHistory(_ book: Book, context: ModelContext) throws {
        book.isHistory = false
        if book.isOnShelf {
            try context.save()
        } else {
            try deleteBookComplete(book, context: context)
        }
    }

    // Xóa toàn bộ lịch sử
    public func clearAllHistory(historyBooks: [Book], context: ModelContext) throws {
        let toDelete = historyBooks.filter { !$0.isOnShelf }
        let toUpdate = historyBooks.filter { $0.isOnShelf }

        for book in toUpdate {
            book.isHistory = false
        }

        if !toDelete.isEmpty {
            let bookIds = toDelete.map { $0.bookId }
            try deleteBooks(bookIds: bookIds, context: context)
        } else {
            try context.save()
        }
    }

    // Helper xóa hoàn toàn một cuốn sách
    public func deleteBookComplete(_ book: Book, context: ModelContext) throws {
        try deleteBooks(bookIds: [book.bookId], context: context)
    }

    // Xóa hàng loạt sách và thực hiện side-effects
    public func deleteBooks(bookIds: [String], context: ModelContext) throws {
        let uniqueBookIds = Array(Set(bookIds))
        guard !uniqueBookIds.isEmpty else { return }

        // Simulate fetch error for testing
        if let fetchErr = Self.mockFetchError {
            throw fetchErr
        }

        // 1. Fetch từ DB trước
        let descriptor = FetchDescriptor<Book>()
        let allBooks: [Book]
        do {
            allBooks = try context.fetch(descriptor)
        } catch {
            AppLogger.shared.log("❌ [BookStorageManager] Lỗi fetch DB khi xóa sách: \(error.localizedDescription)")
            throw error
        }

        let booksToDelete = allBooks.filter { uniqueBookIds.contains($0.bookId) }
        guard !booksToDelete.isEmpty else {
            // Không tìm thấy cuốn sách nào để xóa -> không làm gì tiếp theo và không xóa file vật lý
            return
        }

        // 2. Side effects
        for bookId in uniqueBookIds {
            if TTSManager.shared.playingBookId == bookId {
                TTSManager.shared.stop()
            }
            clearReaderFallback(for: bookId)
            DownloadManager.shared.cancelTasksForBook(bookId: bookId)
        }

        for book in booksToDelete {
            context.delete(book)
        }

        // Simulate save error for testing
        if let saveErr = Self.mockSaveError {
            throw saveErr
        }

        // 3. Save context (DB commit first)
        do {
            try context.save()
        } catch {
            AppLogger.shared.log("❌ [BookStorageManager] Lỗi lưu DB khi xóa sách: \(error.localizedDescription)")
            throw error
        }

        // 4. Cleanup file vật lý bất đồng bộ trong background thread
        Task.detached(priority: .background) {
            for bookId in uniqueBookIds {
                // Xóa file .bin
                do {
                    try await BookBinManager.shared.deleteBinFile(for: bookId)
                } catch {
                    AppLogger.shared.log("❌ Lỗi xóa file .bin: \(error.localizedDescription)")
                    let binPath = await BookBinManager.shared.binFilePath(for: bookId).path
                    await Self.shared.enqueueFailedDeletionAsync(path: binPath)
                }

                // Xóa file cover
                do {
                    try ImageCacheManager.shared.deleteCover(for: bookId)
                } catch {
                    AppLogger.shared.log("❌ Lỗi xóa cover: \(error.localizedDescription)")
                    let coverPath = ImageCacheManager.shared.localCoverURL(for: bookId).path
                    await Self.shared.enqueueFailedDeletionAsync(path: coverPath)
                }
            }
        }
    }

    private func clearReaderFallback(for bookId: String) {
        UserDefaults.standard.removeObject(forKey: "lastChapterIndex_\(bookId)")
        UserDefaults.standard.removeObject(forKey: "lastParagraphIndex_\(bookId)")
    }

    // RETRY QUEUE
    private let retryQueueKey = "failed_file_deletions_queue"

    public func enqueueFailedDeletion(path: String) {
        var queue = UserDefaults.standard.stringArray(forKey: retryQueueKey) ?? []
        if !queue.contains(path) {
            queue.append(path)
            UserDefaults.standard.set(queue, forKey: retryQueueKey)
        }
    }

    // API hỗ trợ gọi enqueue từ background thread của Task.detached
    private func enqueueFailedDeletionAsync(path: String) {
        Task { @MainActor in
            self.enqueueFailedDeletion(path: path)
        }
    }

    public func drainRetryQueue() {
        let queue = UserDefaults.standard.stringArray(forKey: retryQueueKey) ?? []
        guard !queue.isEmpty else { return }

        var remainingQueue: [String] = []
        let fileManager = FileManager.default

        for path in queue {
            let retryKey = "failed_file_deletions_retry_count_\(path)"
            let retries = UserDefaults.standard.integer(forKey: retryKey)
            if retries >= 3 {
                UserDefaults.standard.removeObject(forKey: retryKey)
                continue
            }

            let fileURL = URL(fileURLWithPath: path)
            let isSafe = validatePathSafetyForRetry(fileURL)

            if isSafe && fileManager.fileExists(atPath: path) {
                do {
                    try fileManager.removeItem(at: fileURL)
                    AppLogger.shared.log("🗑️ Retry xóa file thành công: \(path)")
                    UserDefaults.standard.removeObject(forKey: retryKey)
                } catch {
                    AppLogger.shared.log("❌ Retry xóa file thất bại (lần \(retries + 1)): \(path) - \(error.localizedDescription)")
                    UserDefaults.standard.set(retries + 1, forKey: retryKey)
                    remainingQueue.append(path)
                }
            } else {
                UserDefaults.standard.removeObject(forKey: retryKey)
            }
        }

        UserDefaults.standard.set(remainingQueue, forKey: retryQueueKey)
    }

    private func validatePathSafetyForRetry(_ targetURL: URL) -> Bool {
        let fileManager = FileManager.default
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let appSupport = paths.first else { return false }

        let canonicalRoot = appSupport.standardized.resolvingSymlinksInPath()
        let canonicalTarget = targetURL.standardized.resolvingSymlinksInPath()

        return canonicalTarget.pathComponents.starts(with: canonicalRoot.pathComponents)
    }
}
