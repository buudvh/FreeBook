import Foundation

/// Engine lưu trữ mức thấp — chủ **duy nhất** của file `applicationSupportDirectory/playlists/playlists.json`.
///
/// Chỉ đọc / ghi / mã hoá; không giữ trạng thái. `PlaylistRepository` gọi để nạp và ghi, `BackupPlaylistArchiver` dùng
/// `encode` / `decode` cho mục `library/playlists.json` của bản sao lưu.
///
/// - Ghi `.atomic`: app bị kill giữa lượt ghi không để lại file hỏng.
/// - File đọc lỗi (JSON hỏng) không bị ghi đè âm thầm: `quarantineUnreadableFile()` đổi tên nó sang
///   `playlists.broken-<thời điểm>.json` trước khi repository bắt đầu lại từ rỗng.
enum PlaylistStore {
    static let directoryName = "playlists"
    static let fileName = "playlists.json"

    enum LoadResult {
        case loaded([Playlist])
        /// Chưa có file (chưa tạo playlist nào).
        case missing
        /// Có file nhưng không đọc / giải mã được — chữ lỗi để log.
        case unreadable(String)
    }

    static var directoryURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent(directoryName, isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent(fileName)
    }

    // MARK: - Đọc / ghi file

    static func load() -> LoadResult {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
            return .loaded(try decode(data))
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    static func save(_ playlists: [Playlist]) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encode(playlists)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Đổi tên file hỏng để giữ lại (người dùng / bản sau còn cứu được), rồi repository bắt đầu từ rỗng.
    static func quarantineUnreadableFile() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let target = directoryURL.appendingPathComponent("playlists.broken-\(formatter.string(from: Date())).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: target)
            AppLogger.shared.log("❌ [Playlist] File playlist hỏng, đã cất sang \(target.lastPathComponent)")
        } catch {
            AppLogger.shared.log("❌ [Playlist] Không cất được file playlist hỏng: \(error.localizedDescription)")
        }
    }

    // MARK: - Mã hoá

    static func encode(_ playlists: [Playlist]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(PlaylistLibraryFile(playlists: playlists))
    }

    static func decode(_ data: Data) throws -> [Playlist] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PlaylistLibraryFile.self, from: data).playlists
    }
}
