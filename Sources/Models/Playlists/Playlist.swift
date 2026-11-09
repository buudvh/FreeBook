import Foundation

/// Một playlist của người dùng: tên, loại (Nhạc / Video — không trộn), danh sách mục theo **thứ tự người dùng xếp**.
///
/// Bản ghi bất biến về danh tính (`id`, `kind`, `createdAt`); đổi tên / thêm / bớt / đổi thứ tự chỉ đi qua
/// `PlaylistCoordinator`, đọc qua `PlaylistRepository`. Lưu trong `playlists/playlists.json` (`PlaylistLibraryFile`).
struct Playlist: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let kind: PlaylistKind
    let createdAt: Date
    var updatedAt: Date
    var items: [PlaylistItem]

    init(
        id: UUID = UUID(),
        name: String,
        kind: PlaylistKind,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        items: [PlaylistItem] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, createdAt, updatedAt, items
    }

    /// Khoan dung như `PlaylistItem`: thiếu trường thì lấy mặc định; loại lạ (bản app mới hơn) ⇒ coi như Nhạc thay vì làm
    /// hỏng cả file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = (try? container.decodeIfPresent(PlaylistKind.self, forKey: .kind)) ?? .audio
        let created = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        createdAt = created
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? created
        items = try container.decodeIfPresent([PlaylistItem].self, forKey: .items) ?? []
    }
}
