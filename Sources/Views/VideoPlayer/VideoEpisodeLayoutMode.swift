import Foundation

/// Kiểu hiển thị danh sách tập phim: **Lưới** (ô số tập, như trước khi có tuỳ chọn) hoặc **Danh sách** (hàng như mục lục
/// truyện). Dùng ở sheet "Tất cả tập" của màn xem (`VideoWatchEpisodeSheet`) và panel tập khi xem toàn màn
/// (`VideoEpisodePanel`) — hai chỗ đọc chung một lựa chọn.
///
/// - Nhớ **theo tiện ích** (`packageId`) trong UserDefaults: một từ điển dưới khoá `videoEpisodeLayoutByPackage`
///   (`packageId` có dấu chấm nên không làm khoá `@AppStorage` riêng được).
/// - Chưa chọn / `packageId` rỗng ⇒ Lưới. Chọn lại Lưới thì xoá mục của tiện ích để UserDefaults không giữ bản ghi thừa.
enum VideoEpisodeLayoutMode: String {
    case grid
    case list

    static let `default`: VideoEpisodeLayoutMode = .grid
    private static let defaultsKey = "videoEpisodeLayoutByPackage"

    /// Kiểu còn lại — nút đổi kiểu chuyển qua lại giữa hai kiểu.
    var toggled: VideoEpisodeLayoutMode { self == .grid ? .list : .grid }

    /// Icon của nút đổi kiểu = kiểu **sẽ chuyển sang**.
    var toggleSymbolName: String { self == .grid ? "list.bullet" : "square.grid.2x2" }

    var toggleAccessibilityLabel: String { self == .grid ? "Hiện dạng danh sách" : "Hiện dạng lưới" }

    static func load(packageId: String?) -> VideoEpisodeLayoutMode {
        guard let packageId, !packageId.isEmpty,
              let raw = storedMap()[packageId],
              let mode = VideoEpisodeLayoutMode(rawValue: raw) else { return .default }
        return mode
    }

    static func save(_ mode: VideoEpisodeLayoutMode, packageId: String?) {
        guard let packageId, !packageId.isEmpty else { return }
        var map = storedMap()
        if mode == .default {
            guard map.removeValue(forKey: packageId) != nil else { return }
        } else {
            map[packageId] = mode.rawValue
        }
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }

    private static func storedMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }
}
