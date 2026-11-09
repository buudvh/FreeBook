import Foundation
import Observation

/// Nguồn sự thật **duy nhất** của playlist trong RAM. View đọc `playlists` trong `body` (`@Observable`); mọi thay đổi đi qua
/// `PlaylistCoordinator`, coordinator gọi `commit(_:)` — ghi file trước, ghi được mới đổi bản RAM, nên RAM không bao giờ
/// đi trước đĩa.
///
/// Nạp **đồng bộ một lần** trong `init` (file vài chục KB): lần chạm đầu (tab Playlist, sheet "Thêm vào playlist", khôi phục
/// sao lưu) đã có dữ liệu, không có lượt "chưa nạp" nào để lỡ ghi đè file bằng danh sách rỗng. File hỏng ⇒ cất sang bên
/// (`PlaylistStore.quarantineUnreadableFile`) rồi bắt đầu từ rỗng.
@MainActor
@Observable
final class PlaylistRepository {
    static let shared = PlaylistRepository()

    /// Thứ tự hiện trên tab Playlist (playlist mới thêm ở cuối).
    private(set) var playlists: [Playlist] = []

    private init() {
        playlists = Self.loadFromDisk()
    }

    // MARK: - Đọc

    func playlists(of kind: PlaylistKind) -> [Playlist] {
        playlists.filter { $0.kind == kind }
    }

    func playlist(id: UUID) -> Playlist? {
        playlists.first { $0.id == id }
    }

    /// Mục còn hiện khi công tắc NSFW tắt: bỏ mục của nguồn NSFW (như Bộ sưu tập bỏ truyện của nguồn NSFW).
    nonisolated static func visibleItems(of playlist: Playlist, includeNsfw: Bool) -> [PlaylistItem] {
        guard !includeNsfw else { return playlist.items }
        return playlist.items.filter { !RepositoryFilterPolicy.isNsfwSource(packageId: $0.packageId) }
    }

    // MARK: - Ghi (chỉ `PlaylistCoordinator`)

    /// Ghi file rồi mới đổi bản RAM. Lỗi ghi ⇒ RAM giữ nguyên, lỗi trả về cho coordinator.
    func commit(_ updated: [Playlist]) throws {
        try PlaylistStore.save(updated)
        playlists = updated
    }

    // MARK: - Nạp

    private static func loadFromDisk() -> [Playlist] {
        switch PlaylistStore.load() {
        case .loaded(let playlists):
            AppLogger.shared.log("🎶 [Playlist] Đã nạp \(playlists.count) playlist")
            return playlists
        case .missing:
            return []
        case .unreadable(let message):
            AppLogger.shared.log("❌ [Playlist] Không đọc được playlists.json: \(message)")
            PlaylistStore.quarantineUnreadableFile()
            return []
        }
    }
}
