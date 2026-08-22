import Foundation

/// Quản lý các file `.fbbackup` nằm trong `applicationSupportDirectory/backups`.
/// Chỉ làm việc với file — mọi thứ liên quan tới nội dung archive thuộc worker.
public enum LocalBackupStore {
    public struct Item: Sendable, Identifiable, Equatable {
        public let url: URL
        public let createdAt: Date
        public let byteCount: Int64

        public var id: String { url.lastPathComponent }
        public var name: String { url.lastPathComponent }
        /// Tên không có phần mở rộng — dùng làm giá trị mặc định khi đổi tên.
        public var baseName: String { url.deletingPathExtension().lastPathComponent }
        public var displaySize: String { BackupSizeEstimator.format(byteCount) }

        public init(url: URL, createdAt: Date, byteCount: Int64) {
            self.url = url
            self.createdAt = createdAt
            self.byteCount = byteCount
        }
    }

    /// Mới nhất lên đầu.
    public static func list() -> [Item] {
        let root = BackupPaths.backupsDirectory
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .creationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let items: [Item] = urls.compactMap { url in
            guard url.pathExtension.lowercased() == BackupPaths.fileExtension else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let date = values?.contentModificationDate ?? values?.creationDate ?? Date.distantPast
            return Item(url: url, createdAt: date, byteCount: BackupPaths.fileSize(at: url))
        }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    public static func totalBytes() -> Int64 {
        list().reduce(0) { $0 + $1.byteCount }
    }

    public static func delete(_ item: Item) throws {
        try FileManager.default.removeItem(at: item.url)
    }

    /// Đổi tên trong cùng thư mục. Ném lỗi nếu tên mới đã tồn tại để không âm thầm mất file.
    public static func rename(_ item: Item, to newBaseName: String) throws -> Item {
        let sanitized = sanitize(newBaseName)
        guard !sanitized.isEmpty else { throw Failure.invalidName }

        let target = BackupPaths.backupsDirectory
            .appendingPathComponent(sanitized)
            .appendingPathExtension(BackupPaths.fileExtension)
        guard target != item.url else { return item }
        guard !FileManager.default.fileExists(atPath: target.path) else { throw Failure.nameTaken(sanitized) }

        try FileManager.default.moveItem(at: item.url, to: target)
        return Item(url: target, createdAt: item.createdAt, byteCount: item.byteCount)
    }

    /// Chép file người dùng chọn từ Files vào `backups/` để lần sau khôi phục không cần chọn lại.
    /// Trùng tên thì thêm hậu tố `-1`, `-2`…
    public static func importArchive(from source: URL) throws -> Item {
        let base = sanitize(source.deletingPathExtension().lastPathComponent)
        let root = BackupPaths.backupsDirectory
        var candidate = root.appendingPathComponent(base.isEmpty ? "backup" : base)
            .appendingPathExtension(BackupPaths.fileExtension)
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(base.isEmpty ? "backup" : base)-\(suffix)")
                .appendingPathExtension(BackupPaths.fileExtension)
            suffix += 1
        }

        try FileManager.default.copyItem(at: source, to: candidate)
        return Item(url: candidate, createdAt: Date(), byteCount: BackupPaths.fileSize(at: candidate))
    }

    public enum Failure: LocalizedError {
        case invalidName
        case nameTaken(String)

        public var errorDescription: String? {
            switch self {
            case .invalidName:
                return "Tên file không hợp lệ"
            case .nameTaken(let name):
                return "Đã có bản sao lưu tên \"\(name)\""
            }
        }
    }

    private static func sanitize(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: forbidden)
            .joined(separator: "_")
    }
}
