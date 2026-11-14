import Foundation
import SwiftData

/// Hai lối kết thúc của một lượt đổi nguồn: tiến (dọn truyện cũ sau mốc chốt) và lùi (xoá truyện mới trước mốc chốt).
/// Cả hai chạy lại được nhiều lần: app chết giữa chừng thì lần mở sau (`recoverIfNeeded`) làm lại từ đầu bước đó.
extension BookSourceChangeCoordinator {
    /// Sau mốc chốt: xoá truyện cũ qua `BookStorageManager` (điều phối viên duy nhất của việc xoá truyện: context nền, huỷ
    /// tải, xoá bìa/bin/mục lục/comic/video/Legado, hàng đợi thử lại), rồi xoá thiết lập riêng của nó.
    /// Xoá lỗi ⇒ giữ nhật ký để lần mở app sau thử lại.
    func finishCommitted(_ journal: BookSourceChangeJournal, container: ModelContainer) async {
        defer { TranslationManager.shared.clearBookDictCache(for: journal.newBookId) }
        guard !journal.keepsOldBook else {
            AppLogger.shared.log("[SourceChange] Giữ truyện cũ \(journal.oldBookId) (có chương chép lỗi)")
            BookSourceChangeJournal.clear()
            return
        }

        let oldBookId = journal.oldBookId
        if await Self.bookExists(bookId: oldBookId, container: container) {
            do {
                let deleted = try await BookStorageManager.shared.deleteBooksAsync(bookIds: [oldBookId], container: container)
                guard deleted > 0 else {
                    // `deleteBooksAsync` không bao giờ xoá truyện đang nghe TTS ⇒ giữ lại, cùng luật lúc bấm đổi.
                    AppLogger.shared.log("[SourceChange] Truyện cũ \(oldBookId) đang phát TTS, giữ lại")
                    BookSourceChangeJournal.clear()
                    return
                }
            } catch {
                AppLogger.shared.log("❌ [SourceChange] Lỗi xoá truyện cũ, sẽ thử lại lần mở app sau: \(error.localizedDescription)")
                return
            }
        } else {
            // Lần trước đã xoá bản ghi nhưng app có thể chết trước khi kịp xoá file của nó.
            await Self.removeStoredFiles(bookId: oldBookId)
        }

        await BookSourceMigrator.shared.removeBookScopedSettings(bookId: oldBookId)
        TranslateUtils.clearCache()
        TranslationManager.shared.clearBookDictCache(for: oldBookId)
        BookSourceChangeJournal.clear()
        AppLogger.shared.log("[SourceChange] Đã dọn truyện cũ \(oldBookId) sau khi đổi sang \(journal.newBookId)")
    }

    /// Trước mốc chốt: truyện cũ chưa bị đụng tới. Lượt này tạo ra truyện đích ⇒ xoá nó cùng chương đã chép và thiết lập đã
    /// chép; dùng lại truyện có sẵn ⇒ giữ nguyên (chương chép vào đều đúng vị trí, thiết lập chỉ thêm chỗ còn thiếu).
    func rollBack(_ journal: BookSourceChangeJournal, container: ModelContainer) async {
        if journal.createdNewBook {
            let newBookId = journal.newBookId
            if await Self.bookExists(bookId: newBookId, container: container) {
                do {
                    _ = try await BookStorageManager.shared.deleteBooksAsync(bookIds: [newBookId], container: container)
                } catch {
                    AppLogger.shared.log("❌ [SourceChange] Lỗi xoá truyện mới khi lùi lại, sẽ thử lại lần mở app sau: \(error.localizedDescription)")
                    return
                }
            } else {
                // Chết trước khi lưu xong bản ghi `Book`: mục lục / file `.bin` có thể đã kịp ghi.
                await Self.removeStoredFiles(bookId: newBookId)
            }
            await BookSourceMigrator.shared.removeBookScopedSettings(bookId: newBookId)
            TranslationManager.shared.clearBookDictCache(for: newBookId)
        }
        BookSourceChangeJournal.clear()
        AppLogger.shared.log("[SourceChange] Đã lùi lượt đổi nguồn dở \(journal.oldBookId) → \(journal.newBookId), truyện cũ giữ nguyên")
    }

    /// File của một truyện **không còn** bản ghi `Book` — cùng danh sách `BookStorageManager` dọn sau khi xoá bản ghi.
    nonisolated static func removeStoredFiles(bookId: String) async {
        do {
            try await ChapterStore.shared.deleteBook(bookId: bookId)
        } catch {
            AppLogger.shared.log("❌ [SourceChange] Lỗi xoá mục lục của truyện \(bookId): \(error.localizedDescription)")
            await MainActor.run { BookStorageManager.shared.enqueueFailedChapterStoreDeletion(bookId: bookId) }
        }
        do {
            try await BookBinManager.shared.deleteBinFile(for: bookId)
        } catch {
            AppLogger.shared.log("❌ [SourceChange] Lỗi xoá file .bin của truyện \(bookId): \(error.localizedDescription)")
            let binPath = await BookBinManager.shared.binFilePath(for: bookId).path
            await MainActor.run { BookStorageManager.shared.enqueueFailedDeletion(path: binPath) }
        }
        try? ImageCacheManager.shared.deleteCover(for: bookId)
        do {
            try ComicOfflineStore.deleteBook(bookId: bookId)
        } catch {
            AppLogger.shared.log("❌ [SourceChange] Lỗi xoá ảnh comic offline của truyện \(bookId): \(error.localizedDescription)")
        }
        do {
            try VideoOfflineStore.deleteBook(bookId: bookId)
        } catch {
            AppLogger.shared.log("❌ [SourceChange] Lỗi xoá phim tải offline của truyện \(bookId): \(error.localizedDescription)")
        }
        await BookStorageManager.deleteLegadoState(bookId: bookId)
    }
}
