import Foundation

/// Chủ **mọi thao tác ghi** playlist: tạo, đổi tên, xoá playlist; thêm nhiều mục (bỏ mục trùng), bỏ mục, đổi thứ tự; gộp
/// playlist từ bản sao lưu. Mỗi thao tác dựng bản mới của cả danh sách rồi `PlaylistRepository.commit` (ghi file nguyên tử
/// trước, RAM sau). Không báo toast (tầng Services) — trả `Result` để màn gọi tự báo.
///
/// Thao tác trên mục nhận **id** chứ không nhận `IndexSet`: View có thể đang lọc bớt mục (NSFW tắt) nên vị trí trên màn
/// không trùng vị trí trong mảng.
@MainActor
final class PlaylistCoordinator {
    static let shared = PlaylistCoordinator()

    /// Tên dài hơn mức này bị cắt (tên hiện trên thẻ hai dòng và tiêu đề trang).
    static let maxNameLength = 80

    struct AddOutcome: Sendable {
        let playlist: Playlist
        /// Số mục thực sự thêm (đã bỏ mục trùng với playlist và trùng nhau trong lượt thêm).
        let added: Int
        let skipped: Int
    }

    struct RestoreOutcome: Sendable {
        let addedPlaylists: Int
        let addedItems: Int
        let error: String?
    }

    private var repository: PlaylistRepository { .shared }

    private init() {}

    // MARK: - Playlist

    func create(name: String, kind: PlaylistKind) -> Result<Playlist, PlaylistError> {
        guard let cleaned = Self.cleanedName(name) else { return .failure(.emptyName) }
        let playlist = Playlist(name: cleaned, kind: kind)
        var updated = repository.playlists
        updated.append(playlist)
        return commit(updated, log: "Tạo playlist '\(cleaned)' (\(kind.rawValue))").map { _ in playlist }
    }

    func rename(playlistId: UUID, to name: String) -> Result<Playlist, PlaylistError> {
        guard let cleaned = Self.cleanedName(name) else { return .failure(.emptyName) }
        var updated = repository.playlists
        guard let position = updated.firstIndex(where: { $0.id == playlistId }) else { return .failure(.notFound) }
        guard updated[position].name != cleaned else { return .success(updated[position]) }
        updated[position].name = cleaned
        updated[position].updatedAt = Date()
        let renamed = updated[position]
        return commit(updated, log: "Đổi tên playlist thành '\(cleaned)'").map { _ in renamed }
    }

    func delete(playlistId: UUID) -> Result<Void, PlaylistError> {
        var updated = repository.playlists
        guard let position = updated.firstIndex(where: { $0.id == playlistId }) else { return .failure(.notFound) }
        let removed = updated.remove(at: position)
        return commit(updated, log: "Xoá playlist '\(removed.name)' (\(removed.items.count) mục)")
    }

    // MARK: - Mục

    /// Thêm vào **cuối** playlist theo thứ tự truyền vào; mục trùng (`PlaylistItem.dedupeKey`) với playlist hoặc với mục
    /// đứng trước trong lượt này bị bỏ. Không thêm được mục nào ⇒ không ghi file, vẫn `success` (`added == 0`).
    func add(_ items: [PlaylistItem], to playlistId: UUID) -> Result<AddOutcome, PlaylistError> {
        var updated = repository.playlists
        guard let position = updated.firstIndex(where: { $0.id == playlistId }) else { return .failure(.notFound) }
        var playlist = updated[position]
        let fresh = Self.missingItems(items, existing: playlist.items)
        guard !fresh.isEmpty else {
            return .success(AddOutcome(playlist: playlist, added: 0, skipped: items.count))
        }
        playlist.items.append(contentsOf: fresh)
        playlist.updatedAt = Date()
        updated[position] = playlist
        let outcome = AddOutcome(playlist: playlist, added: fresh.count, skipped: items.count - fresh.count)
        return commit(updated, log: "Thêm \(fresh.count) mục vào '\(playlist.name)' (bỏ \(outcome.skipped) mục trùng)")
            .map { _ in outcome }
    }

    func removeItems(ids: Set<UUID>, from playlistId: UUID) -> Result<Void, PlaylistError> {
        guard !ids.isEmpty else { return .success(()) }
        var updated = repository.playlists
        guard let position = updated.firstIndex(where: { $0.id == playlistId }) else { return .failure(.notFound) }
        let before = updated[position].items.count
        updated[position].items.removeAll { ids.contains($0.id) }
        let removed = before - updated[position].items.count
        guard removed > 0 else { return .success(()) }
        updated[position].updatedAt = Date()
        return commit(updated, log: "Bỏ \(removed) mục khỏi '\(updated[position].name)'")
    }

    /// `orderedIds` = thứ tự mới của **các mục đang hiện** (có thể chỉ là một phần khi đang ẩn mục NSFW). Mục không có
    /// trong danh sách giữ nguyên chỗ; các mục có trong danh sách được xếp lại vào đúng những ô chúng đang chiếm.
    func reorderItems(in playlistId: UUID, orderedIds: [UUID]) -> Result<Void, PlaylistError> {
        var updated = repository.playlists
        guard let position = updated.firstIndex(where: { $0.id == playlistId }) else { return .failure(.notFound) }
        let items = updated[position].items
        let reordered = Self.reordered(items, orderedIds: orderedIds)
        guard reordered != items else { return .success(()) }
        updated[position].items = reordered
        updated[position].updatedAt = Date()
        return commit(updated, log: "Đổi thứ tự mục của '\(updated[position].name)'")
    }

    // MARK: - Sao lưu

    /// Gộp playlist của bản sao lưu — **chỉ thêm, không xoá, không ghi đè** (nguyên tắc chung của khôi phục): playlist
    /// chưa có (theo `id`) ⇒ thêm nguyên; đã có ⇒ thêm vào cuối những mục còn thiếu (theo `dedupeKey`), giữ tên trên máy.
    func mergeRestored(_ restored: [Playlist]) -> RestoreOutcome {
        var updated = repository.playlists
        var addedPlaylists = 0
        var addedItems = 0
        for incoming in restored {
            if let position = updated.firstIndex(where: { $0.id == incoming.id }) {
                let fresh = Self.missingItems(incoming.items, existing: updated[position].items)
                guard !fresh.isEmpty else { continue }
                updated[position].items.append(contentsOf: fresh)
                updated[position].updatedAt = max(updated[position].updatedAt, incoming.updatedAt)
                addedItems += fresh.count
            } else {
                var playlist = incoming
                playlist.items = Self.missingItems(incoming.items, existing: [])
                if playlist.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    playlist.name = "Playlist"
                }
                updated.append(playlist)
                addedPlaylists += 1
                addedItems += playlist.items.count
            }
        }
        guard addedPlaylists > 0 || addedItems > 0 else {
            return RestoreOutcome(addedPlaylists: 0, addedItems: 0, error: nil)
        }
        switch commit(updated, log: "Khôi phục \(addedPlaylists) playlist mới, \(addedItems) mục") {
        case .success:
            return RestoreOutcome(addedPlaylists: addedPlaylists, addedItems: addedItems, error: nil)
        case .failure(let error):
            return RestoreOutcome(addedPlaylists: 0, addedItems: 0, error: error.localizedDescription)
        }
    }

    // MARK: - Nội bộ

    private func commit(_ updated: [Playlist], log message: String) -> Result<Void, PlaylistError> {
        do {
            try repository.commit(updated)
            AppLogger.shared.log("🎶 [Playlist] \(message)")
            return .success(())
        } catch {
            AppLogger.shared.log("❌ [Playlist] Không ghi được playlists.json (\(message)): \(error.localizedDescription)")
            return .failure(.saveFailed(error.localizedDescription))
        }
    }

    private static func cleanedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength))
    }

    /// Mục của `incoming` chưa có trong `existing` và chưa xuất hiện trước đó trong chính `incoming`.
    private static func missingItems(_ incoming: [PlaylistItem], existing: [PlaylistItem]) -> [PlaylistItem] {
        var seen = Set(existing.map(\.dedupeKey))
        var result: [PlaylistItem] = []
        for item in incoming where seen.insert(item.dedupeKey).inserted {
            result.append(item)
        }
        return result
    }

    private static func reordered(_ items: [PlaylistItem], orderedIds: [UUID]) -> [PlaylistItem] {
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        let moving = orderedIds.compactMap { id -> PlaylistItem? in
            guard seen.insert(id).inserted else { return nil }
            return byId[id]
        }
        let movingIds = Set(moving.map(\.id))
        let slots = items.indices.filter { movingIds.contains(items[$0].id) }
        guard slots.count == moving.count else { return items }
        var result = items
        for (slot, item) in zip(slots, moving) {
            result[slot] = item
        }
        return result
    }
}
