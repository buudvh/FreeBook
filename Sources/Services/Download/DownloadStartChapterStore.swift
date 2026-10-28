import Foundation

/// Chương bắt đầu của tác vụ tải/xuất truyện chữ hoặc truyện tranh khi người dùng chọn **một chương cụ thể** ở sheet
/// tải (1.3.624). Lưu sidecar theo `taskId` trong UserDefaults để không thêm cột vào `DownloadTaskModel` (không có
/// `VersionedSchema`), cùng kiểu `VideoDownloadRequestStore` của video.
///
/// - Giá trị là `index` thật của chương trong mục lục, không phải vị trí mảng.
/// - Ghi **trước** `enqueueTask`, vì tác vụ có thể chạy ngay.
/// - Giữ tới khi tác vụ bị xoá khỏi tab Tải: thử lại hay mở lại app vẫn bắt đầu đúng chương.
enum DownloadStartChapterStore {
    private static let defaultsKey = "downloadStartChapterIndex"

    static func setStartChapter(_ chapterIndex: Int, taskId: UUID) {
        var map = storedMap()
        map[taskId.uuidString] = chapterIndex
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }

    static func startChapter(taskId: UUID) -> Int? {
        storedMap()[taskId.uuidString]
    }

    static func remove(taskIds: [UUID]) {
        var map = storedMap()
        guard !map.isEmpty else { return }
        let before = map.count
        for taskId in taskIds {
            map.removeValue(forKey: taskId.uuidString)
        }
        guard map.count != before else { return }
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }

    /// Vị trí trong `chapters` (đã sắp theo mục lục) mà tác vụ bắt đầu.
    ///
    /// Thứ tự ưu tiên:
    /// 1. Chương đã chọn ở sheet: chương đầu tiên có `index` ≥ chương đó.
    /// 2. `startFromCurrent`: vị trí = `Book.currentChapterIndex`, như trước 1.3.624.
    /// 3. Đầu mục lục.
    ///
    /// Trả `chapters.count` khi chương đã chọn nằm ngoài mục lục, để caller báo lỗi "vượt quá".
    static func startPosition(
        in chapters: [StoredChapterSnapshot],
        taskId: UUID,
        startFromCurrent: Bool,
        currentIndex: Int
    ) -> Int {
        if let chosen = startChapter(taskId: taskId) {
            return chapters.firstIndex(where: { $0.index >= chosen }) ?? chapters.count
        }
        return startFromCurrent ? currentIndex : 0
    }

    private static func storedMap() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Int] ?? [:]
    }
}
