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

    // Xóa sách khỏi kệ (Hard Delete, trừ sách đang phát TTS)
    public func removeFromShelf(_ book: Book, context: ModelContext) throws {
        try deleteBookComplete(book, context: context)
    }

    // Xóa sách khỏi lịch sử (Hard Delete, trừ sách đang phát TTS)
    public func removeFromHistory(_ book: Book, context: ModelContext) throws {
        try deleteBookComplete(book, context: context)
    }

    // Xóa toàn bộ lịch sử (Chỉ xóa sách không ở trên kệ, trừ sách đang phát TTS)
    public func clearAllHistory(historyBooks: [Book], context: ModelContext) throws {
        let playingId = TTSManager.shared.playingBookId
        let toDelete = historyBooks.filter { !$0.isOnShelf && (playingId.isEmpty || $0.bookId != playingId) }
        guard !toDelete.isEmpty else { return }
        let bookIds = toDelete.map { $0.bookId }
        try deleteBooks(bookIds: bookIds, context: context)
    }

    // Helper xóa hoàn toàn một cuốn sách
    public func deleteBookComplete(_ book: Book, context: ModelContext) throws {
        try deleteBooks(bookIds: [book.bookId], context: context)
    }

    // API Xóa bất đồng bộ lõi theo danh sách bookId sử dụng ModelContainer (Non-blocking UI)
    public func deleteBooksAsync(bookIds: [String], container: ModelContainer) async throws {
        let playingId = TTSManager.shared.playingBookId
        let validBookIds = Array(Set(bookIds)).filter { playingId.isEmpty || $0 != playingId }
        guard !validBookIds.isEmpty else { return }

        // 1. Side-effects trên MainActor cho các bookId hợp lệ (không xóa/dừng sách đang phát TTS)
        for bookId in validBookIds {
            clearReaderFallback(for: bookId)
            DownloadManager.shared.cancelTasksForBook(bookId: bookId)
        }

        // 2. DB Cascade Delete trên background context
        try await Task.detached(priority: .userInitiated) {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false

            let descriptor = FetchDescriptor<Book>()
            let allBooks = try bgContext.fetch(descriptor)
            let booksToDelete = allBooks.filter { validBookIds.contains($0.bookId) }

            guard !booksToDelete.isEmpty else { return }

            for book in booksToDelete {
                bgContext.delete(book)
            }

            try bgContext.save()
        }.value

        // 3. Physical file cleanup trong background thread
        Task.detached(priority: .background) {
            for bookId in validBookIds {
                do {
                    try await BookBinManager.shared.deleteBinFile(for: bookId)
                } catch {
                    AppLogger.shared.log("❌ Lỗi xóa file .bin: \(error.localizedDescription)")
                    let binPath = await BookBinManager.shared.binFilePath(for: bookId).path
                    await Self.shared.enqueueFailedDeletionAsync(path: binPath)
                }

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

    // Async wrapper xóa 1 cuốn sách theo bookId
    public func deleteBookAsync(bookId: String, container: ModelContainer) async throws {
        try await deleteBooksAsync(bookIds: [bookId], container: container)
    }

    // Async clear-all lịch sử chỉ xóa sách không nằm trên kệ (và không phải sách đang phát TTS)
    public func clearAllOffShelfHistoryAsync(container: ModelContainer) async throws {
        let playingId = TTSManager.shared.playingBookId

        let deletedIds: [String] = try await Task.detached(priority: .userInitiated) {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false

            let descriptor = FetchDescriptor<Book>()
            let allBooks = try bgContext.fetch(descriptor)
            let targetBooks = allBooks.filter { !$0.isOnShelf && (playingId.isEmpty || $0.bookId != playingId) }
            let targetIds = targetBooks.map { $0.bookId }

            guard !targetIds.isEmpty else { return [] }

            for book in targetBooks {
                bgContext.delete(book)
            }

            try bgContext.save()
            return targetIds
        }.value

        guard !deletedIds.isEmpty else { return }

        // MainActor side effects
        for bookId in deletedIds {
            clearReaderFallback(for: bookId)
            DownloadManager.shared.cancelTasksForBook(bookId: bookId)
        }

        // Background physical file cleanup
        Task.detached(priority: .background) {
            for bookId in deletedIds {
                do {
                    try await BookBinManager.shared.deleteBinFile(for: bookId)
                } catch {
                    AppLogger.shared.log("❌ Lỗi xóa file .bin: \(error.localizedDescription)")
                    let binPath = await BookBinManager.shared.binFilePath(for: bookId).path
                    await Self.shared.enqueueFailedDeletionAsync(path: binPath)
                }

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

    // Xóa hàng loạt sách và thực hiện side-effects (Đồng bộ)
    public func deleteBooks(bookIds: [String], context: ModelContext) throws {
        let playingId = TTSManager.shared.playingBookId
        let uniqueBookIds = Array(Set(bookIds)).filter { playingId.isEmpty || $0 != playingId }
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
            return
        }

        // 2. Side effects
        for bookId in uniqueBookIds {
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
