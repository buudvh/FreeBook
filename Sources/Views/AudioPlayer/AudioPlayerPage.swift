import Foundation

/// Ba trang vuốt ngang của màn nghe (`AudioPlayerScreen`). Thứ tự khai báo = thứ tự trang (và thứ tự chấm chỉ trang);
/// màn mở vào trang giữa (`disc`).
enum AudioPlayerPage: Int, CaseIterable, Hashable {
    case playlist
    case disc
    case lyrics

    /// Nhãn VoiceOver của chấm chỉ trang.
    var title: String {
        switch self {
        case .playlist: return "Danh sách phát"
        case .disc: return "Đĩa nhạc"
        case .lyrics: return "Lời bài hát"
        }
    }
}
