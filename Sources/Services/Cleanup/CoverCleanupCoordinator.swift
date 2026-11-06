import Foundation
import SwiftData

/// Lượt dọn **bìa truyện** (`covers/`, 1.3.762): xoá bìa mồ côi rồi thu nhỏ bìa còn dùng mà quá cỡ.
///
/// Bìa mồ côi chủ yếu đến từ trang Chi tiết của truyện chưa lưu: trước 1.3.762 nó ghi bìa theo `bookId` ngẫu nhiên mỗi
/// lần mở (từ 1.3.762 chỉ giữ trong RAM — `BookCoverView.persistsCover`). Truyện ẩn (không ở Kệ, không ở Lịch sử) vẫn
/// còn bản ghi `Book` nên bìa của nó **có chủ**, không bị đụng.
///
/// Chỉ điều phối: đọc danh sách `bookId` trên `ModelContext` riêng ngoài main, mọi thao tác file nằm ở owner
/// (`ImageCacheManager+Maintenance`, qua `validatePathSafety`). Không đọc được thư viện ⇒ không dọn gì (thư viện
/// "rỗng" vì lỗi sẽ biến mọi bìa thành mồ côi). Không gọi toast: trả kết quả cho View.
@MainActor
enum CoverCleanupCoordinator {
    /// File ghi / chuyển vào `covers/` chưa quá chừng này thì chưa coi là mồ côi.
    static let minimumFileAge: TimeInterval = 10 * 60

    struct CleanupResult: Sendable, Equatable {
        let removedCount: Int
        let removedBytes: Int64
        let shrunkCount: Int
        let savedBytes: Int64

        var freedBytes: Int64 { removedBytes + savedBytes }
    }

    /// Đang có lượt dọn bìa (bấm tay hoặc lịch tự dọn) — lượt thứ hai bỏ qua thay vì xoá chồng.
    private(set) static var isRunning = false

    /// Đếm trước khi dọn. `nil` ⇒ không đọc được thư viện.
    static func preview(container: ModelContainer, includeOversized: Bool) async -> CoverFolderScan? {
        guard let owned = await ownedBookIds(container: container) else { return nil }
        let minimumAge = minimumFileAge
        return await Task.detached(priority: .utility) {
            ImageCacheManager.shared.scanCoverFolder(ownedBookIds: owned, minimumAge: minimumAge, includeOversized: includeOversized)
        }.value
    }

    /// Dọn theo bản đếm `scan` (đã cho người dùng xem). `nil` ⇒ đang có lượt khác hoặc không đọc được thư viện.
    static func run(_ scan: CoverFolderScan, container: ModelContainer) async -> CleanupResult? {
        guard !isRunning else { return nil }
        isRunning = true
        defer { isRunning = false }
        // Đọc lại thư viện ngay trước khi xoá: truyện có thể vừa được lưu sau lúc đếm.
        guard let owned = await ownedBookIds(container: container) else { return nil }
        let minimumAge = minimumFileAge
        let result = await Task.detached(priority: .utility) { () -> CleanupResult in
            let cache = ImageCacheManager.shared
            let removed = cache.removeOrphanCovers(in: scan, ownedBookIds: owned, minimumAge: minimumAge)
            let shrunk = cache.shrinkOversizedCovers(in: scan)
            return CleanupResult(removedCount: removed.count, removedBytes: removed.bytes, shrunkCount: shrunk.count, savedBytes: shrunk.savedBytes)
        }.value
        AppLogger.shared.log(
            "🧹 [CoverCleanup] Xoá \(result.removedCount) bìa mồ côi (\(result.removedBytes) B), "
            + "thu nhỏ \(result.shrunkCount) bìa quá cỡ (bớt \(result.savedBytes) B)"
        )
        return result
    }

    /// Đếm rồi dọn luôn (lịch tự dọn — không có hộp xác nhận).
    static func runUnattended(container: ModelContainer, includeOversized: Bool) async -> CleanupResult? {
        guard !isRunning, let scan = await preview(container: container, includeOversized: includeOversized) else { return nil }
        guard !scan.isEmpty else { return CleanupResult(removedCount: 0, removedBytes: 0, shrunkCount: 0, savedBytes: 0) }
        return await run(scan, container: container)
    }

    /// Mọi `Book.bookId` của thư viện, đọc trên `ModelContext` riêng ngoài main. `nil` khi fetch lỗi.
    private static func ownedBookIds(container: ModelContainer) async -> Set<String>? {
        await Task.detached(priority: .utility) { () -> Set<String>? in
            let context = ModelContext(container)
            context.autosaveEnabled = false
            var descriptor = FetchDescriptor<Book>()
            descriptor.propertiesToFetch = [\.bookId]
            do {
                return Set(try context.fetch(descriptor).map(\.bookId))
            } catch {
                AppLogger.shared.log("❌ [CoverCleanup] Không đọc được thư viện, bỏ qua lượt dọn bìa: \(error.localizedDescription)")
                return nil
            }
        }.value
    }
}
