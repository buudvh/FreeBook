import Foundation
import SwiftData

/// Lượt dọn **truyện lâu không đọc**: quét phần **lịch sử** của thư viện (truyện không nằm trên Kệ
/// sách), chọn truyện có `lastReadDate` cũ hơn ngưỡng rồi giao cho `BookStorageManager` xoá.
///
/// Truyện trên Kệ sách (`Book.isOnShelf`) **không bao giờ** bị lượt này chạm tới.
///
/// Cùng khuôn với lượt tự động sao lưu Drive: cửa mở/đóng do
/// [`StaleBookCleanupPolicy`](StaleBookCleanupPolicy.swift) quyết định, và hàm **trả về** kết quả cho
/// View tự hiện toast — `Sources/Services/**` không được gọi `ToastManager`.
///
/// Chỉ điều phối: mọi việc xoá thật (DB → file .bin → ChapterStore → cover → retry queue) vẫn nằm ở
/// `BookStorageManager`, đây không tự chạm file hay `ModelContext.delete` nào.
@MainActor
enum StaleBookCleanupCoordinator {
    enum Outcome: Sendable, Equatable {
        /// Chưa tới lượt, đã quét mà không có truyện nào đủ cũ, hoặc mọi truyện đã chọn đều bị loại
        /// ngay lúc xoá (TTS vừa phát một trong số đó) — không có gì bị xoá, View im lặng.
        case skipped
        case deleted(count: Int)
        case failed(message: String)
    }

    /// Lượt **tự động** lúc mở app.
    static func runIfDue(container: ModelContainer) async -> Outcome {
        guard StaleBookCleanupPolicy.shouldRun() else { return .skipped }
        // Đánh dấu trước khi làm việc: lượt lỗi thì chờ tới kỳ sau chứ không quét lại mỗi lần mở app.
        StaleBookCleanupPolicy.markRun()
        return await run(container: container)
    }

    /// Đường bấm tay trong Cài đặt: bỏ qua nhịp chờ và cả cờ bật/tắt, nhưng vẫn tính là lượt của kỳ này.
    static func runNow(container: ModelContainer) async -> Outcome {
        StaleBookCleanupPolicy.markRun()
        return await run(container: container)
    }

    /// Số truyện sẽ bị xoá nếu chạy ngay lúc này — dùng để cảnh báo trước trong Cài đặt.
    static func previewStaleCount(container: ModelContainer) async -> Int {
        guard let cutoff = StaleBookCleanupPolicy.cutoffDate() else { return 0 }
        do {
            return try await staleBookIds(cutoff: cutoff, protectedIds: protectedBookIds(), container: container).count
        } catch {
            AppLogger.shared.log("🧹 [Cleanup] Không đếm được truyện bỏ quên: \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - Lõi

    private static func run(container: ModelContainer) async -> Outcome {
        let thresholdDays = StaleBookCleanupPolicy.inactiveDays
        guard let cutoff = StaleBookCleanupPolicy.cutoffDate(days: thresholdDays) else {
            return .failed(message: "Không tính được mốc thời gian dọn dẹp")
        }

        let protectedIds = protectedBookIds()
        do {
            let staleIds = try await staleBookIds(cutoff: cutoff, protectedIds: protectedIds, container: container)
            guard !staleIds.isEmpty else {
                AppLogger.shared.log("🧹 [Cleanup] Không có truyện nào quá \(thresholdDays) ngày không đọc")
                return .skipped
            }

            // Số báo cho người dùng lấy từ chính `BookStorageManager`, không phải `staleIds.count`:
            // TTS có thể bắt đầu phát một trong các truyện này ngay giữa lúc quét và lúc xoá, và
            // truyện đang phát thì bị loại ở đó chứ không loại ở đây.
            let deletedCount = try await BookStorageManager.shared.deleteBooksAsync(bookIds: staleIds, container: container)
            guard deletedCount > 0 else {
                AppLogger.shared.log("🧹 [Cleanup] Không xoá được truyện nào (đều bị loại lúc xoá)")
                return .skipped
            }
            AppLogger.shared.log(
                "🧹 [Cleanup] Đã xoá \(deletedCount) truyện quá \(thresholdDays) ngày không đọc"
                + "; bỏ qua \(protectedIds.count) truyện đang tải/đang đọc TTS"
            )
            return .deleted(count: deletedCount)
        } catch {
            AppLogger.shared.log("🧹 [Cleanup] Thất bại: \(error.localizedDescription)")
            return .failed(message: error.localizedDescription)
        }
    }

    /// Truyện **không bao giờ** được dọn tự động vì đang có việc chạy trên nó:
    /// * đang được TTS phát (hoặc còn widget nổi giữ phiên) — xoá là cắt ngang phiên đọc,
    /// * đang chờ/đang chạy một tác vụ tải hoặc xuất ebook trong hàng đợi `DownloadManager`.
    ///
    /// `BookStorageManager` cũng tự loại truyện đang phát TTS, nhưng lọc sẵn ở đây để số đếm báo cho
    /// người dùng khớp với số truyện thật sự bị xoá.
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

    /// Quét trên `ModelContext` **riêng** dựng từ `ModelContainer` (tác vụ nền không dùng context của
    /// MainActor), fetch toàn bảng rồi lọc **trên RAM** — predicate lọc trên iOS 17 không đáng tin.
    private static func staleBookIds(
        cutoff: Date,
        protectedIds: Set<String>,
        container: ModelContainer
    ) async throws -> [String] {
        try await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let books = try context.fetch(FetchDescriptor<Book>())
            return books.filter { book in
                // Truyện nằm trên Kệ sách là truyện người dùng **cố ý** giữ — theo yêu cầu tường minh,
                // lượt dọn tự động không bao giờ chạm tới nó, dù bỏ quên bao lâu. Chỉ phần lịch sử
                // (`isOnShelf == false`, tức xem qua ở Khám phá rồi rời đi) mới nằm trong tầm dọn.
                guard !book.isOnShelf else { return false }
                // Sách local/TXT import: nguồn gốc nằm ngoài app, xoá là mất vĩnh viễn vì không tải
                // lại được từ đâu. Không bao giờ dọn tự động, kể cả khi đã quên rất lâu.
                guard !book.isLocalBook else { return false }
                guard !protectedIds.contains(book.bookId) else { return false }
                return book.lastReadDate < cutoff
            }.map { $0.bookId }
        }.value
    }
}
