import Foundation

/// Tập bắt đầu của tác vụ tải video khi người dùng chọn **một tập cụ thể** ("Tải tập này") — sidecar theo `taskId` trong
/// UserDefaults, để không thêm cột vào `DownloadTaskModel` (không có `VersionedSchema`). Tác vụ không có mục ở đây thì
/// dùng `startFromCurrent`/`limit` như truyện. Giữ tới khi tác vụ bị xoá khỏi tab Tải (thử lại sau khi khởi động lại app
/// vẫn đúng tập).
enum VideoDownloadRequestStore {
    private static let defaultsKey = "videoDownloadStartEpisode"

    static func setStartEpisode(_ episodeIndex: Int, taskId: UUID) {
        var map = storedMap()
        map[taskId.uuidString] = episodeIndex
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }

    static func startEpisode(taskId: UUID) -> Int? {
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

    private static func storedMap() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Int] ?? [:]
    }
}
