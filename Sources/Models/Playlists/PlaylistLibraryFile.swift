import Foundation

/// Hình dạng của file `playlists/playlists.json` (và mục `library/playlists.json` trong bản sao lưu): số phiên bản +
/// mảng playlist theo thứ tự hiện trên tab Playlist.
///
/// Bọc trong object thay vì mảng trần để đổi hình dạng về sau còn biết file thuộc phiên bản nào.
struct PlaylistLibraryFile: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var playlists: [Playlist]

    init(playlists: [Playlist]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.playlists = playlists
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, playlists
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        playlists = try container.decodeIfPresent([Playlist].self, forKey: .playlists) ?? []
    }
}
