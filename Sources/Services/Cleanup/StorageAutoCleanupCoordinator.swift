import Foundation
import SwiftData

/// Lượt **tự động dọn dung lượng** (1.3.762): theo lịch của [`StorageAutoCleanupPolicy`](StorageAutoCleanupPolicy.swift)
/// dọn các mục người dùng bật.
///
/// - Bìa truyện ⇒ `CoverCleanupCoordinator` (bìa mồ côi + thu nhỏ bìa quá cỡ), không bao giờ xoá bìa của truyện còn
///   trong thư viện.
/// - Cache ảnh truyện tranh, file xuất, nhật ký, báo cáo kiểm tra ⇒ `StorageUsageCleaner` (đúng đường xoá của nút "Xoá"
///   ở màn Dung lượng).
///
/// Dung lượng giải phóng đo bằng `StorageUsageScanner` trước/sau trên đúng các thư mục của mục được dọn. Không gọi toast
/// (lượt tự động chạy im lặng, chỉ ghi log); màn cài đặt đọc `lastRunAt` / `lastFreedBytes`.
@MainActor
enum StorageAutoCleanupCoordinator {
    enum Outcome: Sendable, Equatable {
        /// Chưa tới kỳ, chưa bật mục nào, hoặc đang có lượt dọn bìa khác.
        case skipped
        case completed(freedBytes: Int64)
        /// Không đọc được thư viện ⇒ không dọn bìa (các mục khác vẫn dọn).
        case partial(freedBytes: Int64)
    }

    /// Lượt **tự động** lúc mở app: hoãn sau khởi động, chờ sao lưu / khôi phục đang chạy xong (bìa vừa khôi phục chưa có
    /// `Book` thì trông như mồ côi), rồi mới đánh dấu kỳ và dọn.
    static func runIfDue(container: ModelContainer) async -> Outcome {
        guard StorageAutoCleanupPolicy.shouldRun() else { return .skipped }
        try? await Task.sleep(nanoseconds: StorageAutoCleanupPolicy.startupDelayNanoseconds)
        guard !Task.isCancelled else { return .skipped }
        await waitForBackupIdle()
        guard !Task.isCancelled, StorageAutoCleanupPolicy.shouldRun() else { return .skipped }
        StorageAutoCleanupPolicy.markRun()
        return await run(categories: StorageAutoCleanupPolicy.categories, container: container)
    }

    /// Nút "Dọn ngay" ở màn cài đặt: bỏ qua nhịp chờ và cờ bật/tắt, vẫn tính là lượt của kỳ này.
    static func runNow(container: ModelContainer) async -> Outcome {
        StorageAutoCleanupPolicy.markRun()
        return await run(categories: StorageAutoCleanupPolicy.categories, container: container)
    }

    /// Chờ lượt sao lưu / khôi phục / tải lên đang chạy — kiểm tra mỗi 2 s, tối đa ~10 phút (cùng nhịp với dọn truyện cũ).
    static func waitForBackupIdle() async {
        var polls = 0
        while BackupCoordinator.shared.isBusy, !Task.isCancelled, polls < 300 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            polls += 1
        }
    }

    // MARK: - Lõi

    private static func run(categories: Set<StorageUsageCategory>, container: ModelContainer) async -> Outcome {
        let ordered = StorageAutoCleanupPolicy.eligibleCategories.filter { categories.contains($0) }
        guard !ordered.isEmpty else { return .skipped }

        let before = await measure(ordered)
        var coverFailed = false
        for category in ordered {
            if category == .covers {
                if await CoverCleanupCoordinator.runUnattended(container: container, includeOversized: true) == nil {
                    coverFailed = true
                }
            } else {
                await StorageUsageCleaner.clear(category)
            }
        }
        let after = await measure(ordered)
        let freed = max(0, before - after)
        StorageAutoCleanupPolicy.lastFreedBytes = freed
        AppLogger.shared.log(
            "🧹 [StorageAutoCleanup] Dọn \(ordered.map(\.rawValue).joined(separator: ", ")): giải phóng \(freed) B"
            + (coverFailed ? " — bỏ qua bìa (đang có lượt khác hoặc không đọc được thư viện)" : "")
        )
        return coverFailed ? .partial(freedBytes: freed) : .completed(freedBytes: freed)
    }

    /// Tổng dung lượng thật trên đĩa của các mục (ngoài main).
    private static func measure(_ categories: [StorageUsageCategory]) async -> Int64 {
        let locations = categories.flatMap(\.locations)
        return await Task.detached(priority: .utility) {
            locations.reduce(Int64(0)) { $0 + StorageUsageScanner.size(of: $1) }
        }.value
    }
}
