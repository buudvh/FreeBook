import Foundation

/// Một file `.fbbackup` trên Google Drive. `size`/`createdTime` của Drive v3 trả về dạng chuỗi,
/// nên phần giải mã nằm ngay trong type này thay vì rải ra client.
public struct GoogleDriveFile: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let byteCount: Int64
    public let createdAt: Date

    public var displaySize: String { BackupSizeEstimator.format(byteCount) }

    public init(id: String, name: String, byteCount: Int64, createdAt: Date) {
        self.id = id
        self.name = name
        self.byteCount = byteCount
        self.createdAt = createdAt
    }

    /// Trường `files[]` của `GET /drive/v3/files`.
    struct RawEntry: Decodable {
        let id: String
        let name: String
        let size: String?
        let createdTime: String?
    }

    struct ListResponse: Decodable {
        let files: [RawEntry]?
        let nextPageToken: String?
    }

    struct CreateResponse: Decodable {
        let id: String
        let name: String?
    }

    static func make(from raw: RawEntry) -> GoogleDriveFile {
        GoogleDriveFile(
            id: raw.id,
            name: raw.name,
            byteCount: Int64(raw.size ?? "") ?? 0,
            createdAt: parseDate(raw.createdTime)
        )
    }

    private static func parseDate(_ value: String?) -> Date {
        guard let value else { return Date.distantPast }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value) ?? Date.distantPast
    }
}
