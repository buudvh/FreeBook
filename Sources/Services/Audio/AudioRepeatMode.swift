import Foundation

/// Chế độ lặp của trình nghe âm thanh, nhớ **toàn app** (`AudioPlaybackPreferences`). Bấm nút lặp đi vòng
/// `off` → `album` → `one` → `off` (`next`).
///
/// - `off`: hết bài cuối của thứ tự phát ⇒ dừng ở cuối.
/// - `album`: hết bài cuối ⇒ quay về bài đầu (đang xáo trộn thì xáo lại thứ tự mới).
/// - `one`: hết bài ⇒ phát lại chính bài đó. Bấm bài sau / bài trước vẫn chuyển bài như thường.
enum AudioRepeatMode: String, CaseIterable, Sendable {
    case off
    case album
    case one

    /// Chế độ kế tiếp khi bấm nút lặp.
    var next: AudioRepeatMode {
        switch self {
        case .off: return .album
        case .album: return .one
        case .one: return .off
        }
    }

    var title: String {
        switch self {
        case .off: return "Không lặp"
        case .album: return "Lặp album"
        case .one: return "Lặp một bài"
        }
    }

    /// Tên trên nút lặp; đang phát playlist (`PlaylistPlaybackCoordinator`) thì `album` lặp cả playlist.
    func title(inPlaylist: Bool) -> String {
        inPlaylist && self == .album ? "Lặp playlist" : title
    }

    /// SF Symbol của nút lặp (`off` dùng cùng icon với `album`, UI làm mờ).
    var symbolName: String {
        switch self {
        case .off, .album: return "repeat"
        case .one: return "repeat.1"
        }
    }
}
