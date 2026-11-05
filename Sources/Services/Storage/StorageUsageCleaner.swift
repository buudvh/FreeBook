import Foundation

/// Xoá ba loại dữ liệu "an toàn" của màn Dung lượng — dùng lại đúng đường xoá đang có của từng owner, không tự xoá
/// thư mục của người khác:
/// - Cache ảnh truyện tranh ⇒ `ComicImageLoader.clearDiskCache()` (chính instance cache của loader).
/// - File xuất ⇒ `DownloadManager.clearFinishedExportTasks()` (chỉ tác vụ xuất đã xong/lỗi/huỷ + file của chúng; mục mồ
///   côi chỉ dọn khi không còn tác vụ xuất nào chạy).
/// - Nhật ký ⇒ `AppLogger.shared.clear()`.
///
/// Không báo toast (Services không gọi `ToastManager`); màn gọi đo lại rồi tự báo.
public enum StorageUsageCleaner {
    @MainActor
    public static func clear(_ category: StorageUsageCategory) async {
        switch category {
        case .comicImageCache:
            await ComicImageLoader.shared.clearDiskCache()
        case .exports:
            await DownloadManager.shared.clearFinishedExportTasks()
        case .logs:
            AppLogger.shared.clear()
        default:
            return
        }
        AppLogger.shared.log("🧹 [StorageUsage] Đã xoá: \(category.title)")
    }
}
