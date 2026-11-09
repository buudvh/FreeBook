import Foundation

/// Chip đang chọn ở tab Playlist của Kệ sách: **Tất cả** (mặc định, 1.3.810) / Nhạc / Video.
///
/// Kiểu riêng của tầng View — **không** thêm case "tất cả" vào `PlaylistKind` (giá trị đó nằm trong `playlists.json` và
/// làm nguồn cho ô chọn loại). `rawValue` lưu ở `@AppStorage(PlaylistsTabView.kindDefaultsKey)`: `"audio"` / `"video"`
/// trùng `PlaylistKind.rawValue` nên giá trị đã lưu trước 1.3.810 vẫn đọc được; `"all"` là giá trị mới.
enum PlaylistKindFilter: String, CaseIterable, Identifiable {
    case all
    case audio
    case video

    var id: String { rawValue }

    /// `nil` = mọi loại.
    var kind: PlaylistKind? {
        switch self {
        case .all: return nil
        case .audio: return .audio
        case .video: return .video
        }
    }

    var title: String {
        kind?.title ?? "Tất cả"
    }

    /// Icon của chip; "Tất cả" không có (như chip "Tất cả" của `ExtensionKindFilterBar`).
    var symbolName: String? {
        kind?.symbolName
    }

    init(kind: PlaylistKind) {
        switch kind {
        case .audio: self = .audio
        case .video: self = .video
        }
    }

    func matches(_ playlist: Playlist) -> Bool {
        guard let kind else { return true }
        return playlist.kind == kind
    }
}
