import Foundation
import SwiftData

/// Thân của các hành động trên một cuốn sách, dùng chung cho Kệ sách, Lịch sử và màn Bộ sưu tập. Tách
/// ra khỏi `ShelfView` để ba nơi cùng cư xử y hệt nhau — trước đây mỗi màn tự viết lại một bản.
///
/// Mọi lệnh ghi đi qua coordinator; ở đây **không** có `modelContext.save()` nào.
@MainActor
struct BookActionRunner {
    static func togglePin(_ book: Book, in context: ModelContext) {
        let target = !book.isPinned
        let res = BookTransactionCoordinator.shared.setPinned(bookId: book.bookId, isPinned: target, in: context)
        switch res {
        case .success:
            ToastManager.shared.show(message: target ? "Đã ghim lên đầu kệ sách" : "Đã bỏ ghim", type: .success)
        case .failure(let err):
            AppLogger.shared.log("❌ [BookActionRunner] Lỗi ghim truyện: \(err.localizedDescription)")
            ToastManager.shared.show(message: "Không thể ghim: \(err.localizedDescription)", type: .error)
        }
    }

    static func addToShelf(_ book: Book, in context: ModelContext) {
        let res = BookTransactionCoordinator.shared.setOnShelf(bookId: book.bookId, isOnShelf: true, in: context)
        switch res {
        case .success:
            ToastManager.shared.show(
                message: "Đã thêm '\(displayTitle(book))' vào kệ sách",
                type: .success
            )
        case .failure(let err):
            AppLogger.shared.log("❌ [BookActionRunner] Lỗi thêm vào kệ: \(err.localizedDescription)")
            ToastManager.shared.show(message: "Không thể thêm vào kệ sách: \(err.localizedDescription)", type: .error)
        }
    }

    /// Rời kệ nhưng vẫn giữ file/tiến độ (truyện rơi về Lịch sử). Coordinator tự dọn bộ sưu tập.
    static func removeFromShelfOnly(_ book: Book, in context: ModelContext) {
        let res = BookTransactionCoordinator.shared.removeFromShelf(bookId: book.bookId, in: context)
        switch res {
        case .success:
            ToastManager.shared.show(message: "Đã xoá '\(displayTitle(book))' khỏi kệ sách", type: .success)
        case .failure(let err):
            AppLogger.shared.log("❌ [BookActionRunner] Lỗi xoá khỏi kệ sách: \(err.localizedDescription)")
            ToastManager.shared.show(message: "Không thể xoá khỏi kệ sách: \(err.localizedDescription)", type: .error)
        }
    }

    /// Bỏ khỏi lịch sử. Truyện đang ở trên kệ thì chỉ hạ cờ `isHistory`; không thì xoá hẳn khỏi thiết bị.
    /// Trả `true` nếu đã kích hoạt đường xoá bất đồng bộ (người gọi cần bật overlay chờ).
    static func removeFromHistory(_ book: Book, in context: ModelContext) -> Bool {
        guard book.isOnShelf else { return true }
        let res = BookTransactionCoordinator.shared.setHistory(bookId: book.bookId, isHistory: false, in: context)
        switch res {
        case .success:
            ToastManager.shared.show(message: "Đã xóa khỏi lịch sử đọc", type: .success)
        case .failure(let err):
            AppLogger.shared.log("❌ [BookActionRunner] Lỗi xoá lịch sử: \(err.localizedDescription)")
            ToastManager.shared.show(message: "Không thể xoá khỏi lịch sử: \(err.localizedDescription)", type: .error)
        }
        return false
    }

    static func removeFromCollection(_ book: Book, collectionId: String, in context: ModelContext) {
        let res = BookCollectionCoordinator.shared.removeBook(bookId: book.bookId, fromCollection: collectionId, in: context)
        switch res {
        case .success:
            ToastManager.shared.show(message: "Đã bỏ khỏi bộ sưu tập (truyện vẫn ở trên kệ)", type: .success)
        case .failure(let err):
            AppLogger.shared.log("❌ [BookActionRunner] Lỗi bỏ khỏi bộ sưu tập: \(err.localizedDescription)")
            ToastManager.shared.show(message: "Không thể bỏ khỏi bộ sưu tập: \(err.localizedDescription)", type: .error)
        }
    }

    /// Xoá hẳn truyện khỏi thiết bị. `BookStorageManager` là điều phối viên duy nhất của việc này.
    static func deleteBook(bookId: String, container: ModelContainer) async {
        do {
            try await BookStorageManager.shared.deleteBookAsync(bookId: bookId, container: container)
        } catch {
            AppLogger.shared.log("❌ [BookActionRunner] Lỗi khi xoá sách: \(error.localizedDescription)")
        }
    }

    static func retranslateChapterTitles(for book: Book) {
        TranslateUtils.clearChapterTitleCache(for: book.bookId)
        ToastManager.shared.show(message: "Đang dịch lại tên chương...")

        let bookId = book.bookId
        let bookTitle = book.title

        Task {
            guard let storeChaps = try? await ChapterStore.shared.fetchOrderedTOC(bookId: bookId), !storeChaps.isEmpty else { return }

            struct StoreChapterSnapshot: Sendable {
                let index: Int
                let url: String
                let title: String
            }
            let snapshots = storeChaps.map { StoreChapterSnapshot(index: $0.index, url: $0.url, title: $0.title) }

            let updates: [(index: Int, url: String, titleTrans: String)] = await Task.detached(priority: .userInitiated) {
                var list: [(index: Int, url: String, titleTrans: String)] = []
                for snap in snapshots {
                    if Task.isCancelled { break }
                    if !snap.title.isEmpty {
                        let translated = TranslateUtils.translateChapterTitle(snap.title, bookId: bookId)
                        list.append((index: snap.index, url: snap.url, titleTrans: translated))
                    }
                }
                return list
            }.value

            if !updates.isEmpty {
                try? await ChapterStore.shared.updateTitleTranslations(bookId: bookId, updates: updates)
            }

            await MainActor.run {
                ToastManager.shared.show(message: "Đã dịch lại xong tên chương cho: \(TranslateUtils.translateBookTitleIfNeeded(bookTitle, bookId: bookId))")
            }
        }
    }

    static func displayTitle(_ book: Book) -> String {
        TranslateUtils.translateBookTitleIfNeeded(book.title, bookId: book.bookId)
    }

    // MARK: - Chương mới

    /// `nil` khi truyện không thể kiểm tra: truyện nhập cục bộ, thiếu `detailUrl`, hoặc tiện ích bóc
    /// tách chưa tải về máy. Nguồn duy nhất dựng target — `ShelfView+NewChapters` gọi lại hàm này.
    static func newChapterTarget(for book: Book, extensions: [Extension]) -> NewChapterProbe.Target? {
        guard !book.isLocalBook, !book.detailUrl.isEmpty else { return nil }
        guard let ext = extensions.first(where: { $0.packageId == book.extensionPackageId }),
              !ext.localPath.isEmpty else { return nil }

        let host: String?
        if let bookHost = book.host, !bookHost.isEmpty {
            host = bookHost
        } else {
            host = ext.sourceUrl
        }

        return NewChapterProbe.Target(
            bookId: book.bookId,
            title: book.title,
            detailUrl: book.detailUrl,
            host: host,
            snapshot: ExtensionExecutionSnapshot(
                packageId: ext.packageId,
                name: ext.name,
                localPath: ext.localPath,
                downloadUrl: ext.downloadUrl,
                configJson: ext.configJson
            )
        )
    }

    /// Refresh tay một truyện. Dùng cho cả Kệ sách và màn bộ sưu tập.
    static func checkNewChapters(for book: Book, extensions: [Extension]) {
        guard let target = newChapterTarget(for: book, extensions: extensions) else {
            ToastManager.shared.show(message: "Truyện này không kiểm tra được chương mới", type: .error)
            return
        }
        Task {
            guard let summary = await NewChapterInboxManager.shared.check(target: target) else { return }
            showNewChapterSummary(summary, announceEmpty: true)
        }
    }

    /// Một lượt = **một** toast, kể cả khi kiểm tra 20 truyện.
    static func showNewChapterSummary(_ summary: NewChapterInboxManager.BatchSummary, announceEmpty: Bool) {
        if summary.bookCount > 0 {
            let prefix = summary.hasInexact ? "ít nhất " : ""
            let message = summary.bookCount == 1
                ? "1 truyện có \(prefix)\(summary.chapterCount) chương mới"
                : "\(summary.bookCount) truyện có \(prefix)\(summary.chapterCount) chương mới"
            ToastManager.shared.show(message: message, type: .success)
            return
        }

        guard announceEmpty else { return }

        if summary.failureCount > 0 && summary.checkedCount == summary.failureCount {
            ToastManager.shared.show(message: "Không kiểm tra được chương mới", type: .error)
        } else {
            ToastManager.shared.show(message: "Không có chương mới")
        }
    }
}
