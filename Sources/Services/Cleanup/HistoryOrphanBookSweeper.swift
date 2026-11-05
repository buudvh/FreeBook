import Foundation
import SwiftData

/// Lượt dọn **bản ghi sách mồ côi** của tiện ích không lưu lịch sử — chạy một lần mỗi lần mở app.
///
/// Đọc/xem bằng tiện ích tắt "Lưu lịch sử đọc/xem" (`ExtensionHistoryPolicy`) vẫn tạo bản ghi `Book` (mục lục,
/// tiến độ, chương đã tải) nhưng không bật `isHistory`. Sách đó không nằm trên kệ thì không hiện ở đâu cả, nên lượt
/// này xoá hẳn qua `BookStorageManager.deleteBooksAsync` (DB → `.bin` → ChapterStore → bìa).
///
/// Chỉ chọn sách `!isOnShelf && !isHistory && !isLocalBook && !recordsHistory`:
/// - lịch sử cũ (`isHistory == true`) giữ nguyên dù tiện ích đã tắt lưu lịch sử;
/// - sách của tiện ích vẫn lưu lịch sử (kể cả bản ghi tạm của màn Chi tiết) không bị chạm;
/// - bỏ qua sách đang phát TTS / còn widget TTS, và sách có tác vụ tải/xuất đang chờ hoặc đang chạy.
///
/// Gọi **ngay** lúc mở app, sau `DownloadManager.initialize` (danh sách tác vụ mới có), không hoãn: hoãn thì có thể
/// xoá đúng bản ghi người dùng vừa mở ở màn Chi tiết/Reader.
@MainActor
enum HistoryOrphanBookSweeper {
    private static var didStart = false

    /// Chỉ chạy lượt đầu tiên trong tiến trình; các lần gọi sau (view gốc xuất hiện lại) bỏ qua.
    static func startOnce(container: ModelContainer) {
        guard !didStart else { return }
        didStart = true
        Task(priority: .utility) {
            await Self.run(container: container)
        }
    }

    private static func run(container: ModelContainer) async {
        let protectedIds = protectedBookIds()
        do {
            let orphanIds = try await orphanBookIds(protectedIds: protectedIds, container: container)
            guard !orphanIds.isEmpty else { return }
            let deleted = try await BookStorageManager.shared.deleteBooksAsync(bookIds: orphanIds, container: container)
            AppLogger.shared.log(
                "🧹 [HistorySweep] Đã xoá \(deleted)/\(orphanIds.count) bản ghi sách của tiện ích không lưu lịch sử"
            )
        } catch {
            AppLogger.shared.log("❌ 🧹 [HistorySweep] Dọn sách mồ côi thất bại: \(error.localizedDescription)")
        }
    }

    /// Cùng luật với `StaleBookCleanupCoordinator`: sách đang phát TTS (hoặc widget còn giữ phiên) và sách có tác vụ
    /// tải/xuất `pending`/`running`. `BookStorageManager` cũng tự loại sách đang phát TTS.
    private static func protectedBookIds() -> Set<String> {
        var ids: Set<String> = []
        let ttsManager = TTSManager.shared
        if ttsManager.isPlaying || ttsManager.showFloatingWidget {
            let playingId = ttsManager.playingBookId
            if !playingId.isEmpty {
                ids.insert(playingId)
            }
        }
        for task in DownloadManager.shared.tasks where task.status == .pending || task.status == .running {
            ids.insert(task.bookId)
        }
        return ids
    }

    /// Quét trên `ModelContext` **riêng** (tác vụ nền không dùng context của MainActor), fetch toàn bảng rồi lọc
    /// **trên RAM** — predicate lọc trên iOS 17 không đáng tin. `ExtensionHistoryPolicy` đọc bảng chụp có lock.
    private static func orphanBookIds(
        protectedIds: Set<String>,
        container: ModelContainer
    ) async throws -> [String] {
        try await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let books = try context.fetch(FetchDescriptor<Book>())
            return books.filter { book in
                guard !book.isOnShelf, !book.isHistory, !book.isLocalBook else { return false }
                guard !protectedIds.contains(book.bookId) else { return false }
                return !ExtensionHistoryPolicy.recordsHistory(packageId: book.extensionPackageId)
            }.map { $0.bookId }
        }.value
    }
}
