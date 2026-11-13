import Foundation
import SwiftData

/// Lượt quét / dọn của trang **Dọn rác** (Cài đặt › Thư Viện › Dung lượng › Dọn rác). Khuôn `CoverCleanupCoordinator`:
/// đếm trước (`preview`) → người dùng xác nhận → dọn (`run`).
///
/// - Chụp trạng thái bận trên main (`JunkScanInputs.capture`), đọc `bookId` trên `ModelContext` riêng ngoài main; đọc thư
///   viện lỗi ⇒ bỏ nhóm truyện đã xoá (thư viện "rỗng" vì lỗi sẽ biến mọi truyện thành mồ côi).
/// - `run` **quét lại** ngay trước khi xoá (bận / thư viện / tuổi file mới nhất) và chỉ xoá mục có trong **cả** bản người
///   dùng đã xem lẫn bản vừa quét; mỗi mục kiểm lại gốc được phép, danh sách cấm và đường dẫn (giải symlink) ngay trước
///   khi xoá.
/// - Không gọi toast (Services không gọi `ToastManager`): trả kết quả, View tự báo.
@MainActor
enum JunkCleanupCoordinator {
    struct CleanupResult: Sendable, Equatable {
        var removedCount = 0
        var removedBytes: Int64 = 0
        var failedCount = 0
        /// Mục đã xem nhưng lượt quét lại không còn coi là rác (bận, truyện vừa lưu lại…) ⇒ giữ nguyên.
        var skippedCount = 0
        var removedCoreML = false
    }

    /// Đang dọn — lượt thứ hai bỏ qua thay vì xoá chồng.
    private(set) static var isRunning = false

    /// Trạng thái bận + danh sách `bookId` (khi có container) cho một lượt quét.
    static func captureInputs(container: ModelContainer?) async -> JunkScanInputs {
        var owned: Set<String>? = nil
        if let container {
            owned = await ownedBookIds(container: container)
        }
        return JunkScanInputs.capture(ownedBookIds: owned)
    }

    /// Quét cho trang Dọn rác.
    static func preview(container: ModelContainer) async -> JunkScanResult {
        let inputs = await captureInputs(container: container)
        let result = await Task.detached(priority: .utility) { JunkScanner.scan(inputs) }.value
        let groups = result.groups.map { "\($0.kind.rawValue)=\($0.items.count) mục/\($0.bytes) B" }
        AppLogger.shared.log(
            "🧹 [JunkCleanup] Quét: \(result.totalBytes) B"
            + (groups.isEmpty ? "" : " — " + groups.joined(separator: ", "))
            + " · đang chặn: \(inputs.blockedSummary)"
        )
        return result
    }

    /// Dọn theo bản `shown` (đã cho người dùng xem). `nil` ⇒ đang có lượt dọn khác.
    static func run(_ shown: JunkScanResult, container: ModelContainer) async -> CleanupResult? {
        guard !isRunning else { return nil }
        isRunning = true
        defer { isRunning = false }

        let inputs = await captureInputs(container: container)
        let allowedRoots = JunkPaths.allowedRoots.map { $0.standardizedFileURL.path }
        let cacheKey = JunkPaths.coreMLCacheDirectory.standardizedFileURL.path
        let result = await Task.detached(priority: .utility) { () -> CleanupResult in
            let fresh = JunkScanner.scan(inputs)
            var current: [String: (kind: JunkGroupKind, item: JunkScanResult.Item)] = [:]
            for group in fresh.groups {
                for item in group.items { current[item.key] = (group.kind, item) }
            }
            var outcome = CleanupResult()
            var releasedReader = false
            for group in shown.groups {
                for shownItem in group.items {
                    guard let match = current[shownItem.key], match.kind == group.kind else {
                        outcome.skippedCount += 1
                        continue
                    }
                    let item = match.item
                    if match.kind == .coreMLStale {
                        outcome.removedCoreML = true
                        if item.key == cacheKey, !releasedReader {
                            // Backend đang gắn có thể giữ session nạp từ bản biên dịch sắp xoá; lượt đang chạy giữ bản
                            // tham chiếu riêng nên chạy nốt bình thường.
                            VieNeuCoreMLReaderRoute.shared.release(reason: "dọn rác")
                            releasedReader = true
                        }
                    }
                    if JunkCleanupCoordinator.remove(item, allowedRoots: allowedRoots) {
                        outcome.removedCount += 1
                        outcome.removedBytes += item.bytes
                    } else {
                        outcome.failedCount += 1
                    }
                }
            }
            return outcome
        }.value

        if result.removedCoreML {
            // Cài đặt VieNeu hiện lại trạng thái gói / bản biên dịch đúng sau khi dọn.
            VieNeuCoreMLAccelerator.shared.refresh()
        }
        AppLogger.shared.log(
            "🧹 [JunkCleanup] Đã dọn \(result.removedCount) mục (\(result.removedBytes) B), bỏ qua \(result.skippedCount)"
            + " · đang chặn: \(inputs.blockedSummary)"
        )
        if result.failedCount > 0 {
            AppLogger.shared.log("❌ [JunkCleanup] \(result.failedCount) mục không xoá được")
        }
        return result
    }

    /// Xoá một mục sau khi kiểm lại: gốc thuộc danh sách được phép, không thuộc danh sách cấm, còn nằm trong gốc sau khi
    /// giải symlink. Mục đã biến mất tính là xong.
    nonisolated private static func remove(_ item: JunkScanResult.Item, allowedRoots: [String]) -> Bool {
        let fileManager = FileManager.default
        guard allowedRoots.contains(item.root.standardizedFileURL.path),
              !JunkPaths.isProtected(item.url),
              !JunkScanner.isSymbolicLink(item.url) else {
            AppLogger.shared.log("❌ [JunkCleanup] Từ chối xoá \(item.url.lastPathComponent): ngoài gốc được phép / thuộc danh sách cấm")
            return false
        }
        guard fileManager.fileExists(atPath: item.url.path) else { return true }
        guard JunkPaths.isSafelyInside(item.url, root: item.root) else {
            AppLogger.shared.log("❌ [JunkCleanup] Từ chối xoá \(item.url.lastPathComponent): đường dẫn thoát khỏi thư mục gốc")
            return false
        }
        do {
            try fileManager.removeItem(at: item.url)
            return true
        } catch {
            AppLogger.shared.log("❌ [JunkCleanup] Không xoá được \(item.url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }

    /// Mọi `Book.bookId` của thư viện, đọc trên `ModelContext` riêng ngoài main (như `CoverCleanupCoordinator`). `nil` khi
    /// fetch lỗi.
    static func ownedBookIds(container: ModelContainer) async -> Set<String>? {
        await Task.detached(priority: .utility) { () -> Set<String>? in
            let context = ModelContext(container)
            context.autosaveEnabled = false
            var descriptor = FetchDescriptor<Book>()
            descriptor.propertiesToFetch = [\.bookId]
            do {
                return Set(try context.fetch(descriptor).map(\.bookId))
            } catch {
                AppLogger.shared.log("❌ [JunkCleanup] Không đọc được thư viện, bỏ qua dữ liệu của truyện đã xoá: \(error.localizedDescription)")
                return nil
            }
        }.value
    }
}
