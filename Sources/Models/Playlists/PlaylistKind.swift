import Foundation

/// Loại của một playlist: **Nhạc** (bài của tiện ích loại `audio`) hoặc **Video** (tập của tiện ích loại `video`). Hai loại
/// tách hẳn — playlist Nhạc chỉ nhận bài, playlist Video chỉ nhận tập (tab Playlist của Kệ sách lọc theo chip loại).
///
/// Có kiểu riêng thay vì lưu `ExtensionContentKind`: giá trị này nằm trong `playlists/playlists.json`, không được phụ
/// thuộc vào việc enum loại nội dung đổi tên / thêm case. `rawValue` là hợp đồng của file — không đổi.
enum PlaylistKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case audio
    case video

    var id: String { rawValue }

    /// Nhãn chip / ô chọn loại.
    var title: String {
        switch self {
        case .audio: return "Nhạc"
        case .video: return "Video"
        }
    }

    var symbolName: String {
        switch self {
        case .audio: return "music.note"
        case .video: return "play.rectangle"
        }
    }

    /// Danh từ đếm một mục: "12 bài", "8 tập".
    var itemNoun: String {
        switch self {
        case .audio: return "bài"
        case .video: return "tập"
        }
    }

    var contentKind: ExtensionContentKind {
        switch self {
        case .audio: return .audio
        case .video: return .video
        }
    }

    /// `nil` với truyện chữ / truyện tranh / loại lạ — chỉ âm thanh và phim vào được playlist.
    init?(contentKind: ExtensionContentKind) {
        switch contentKind {
        case .audio: self = .audio
        case .video: self = .video
        case .text, .comic, .unsupported: return nil
        }
    }

    /// "12 bài" / "8 tập".
    func countLabel(_ count: Int) -> String {
        "\(count) \(itemNoun)"
    }
}
