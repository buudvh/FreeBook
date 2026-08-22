import Foundation

/// Mô tả một file `.fbbackup`: phiên bản định dạng, thời điểm tạo, nhóm nội dung đã sao lưu
/// và số lượng từng loại để màn Khôi phục tóm tắt trước khi người dùng đồng ý.
public struct BackupManifest: Codable, Sendable {
    /// Tăng khi cây entry trong archive đổi theo cách không đọc ngược được.
    public static let currentSchemaVersion = 1

    public struct Counts: Codable, Sendable {
        public var books: Int
        public var chapters: Int
        public var cachedChapters: Int
        public var repositories: Int
        public var extensions: Int
        public var bookDictionaries: Int
        public var customDictionaries: Int
        public var sharedDictionaries: Int

        public init(
            books: Int = 0,
            chapters: Int = 0,
            cachedChapters: Int = 0,
            repositories: Int = 0,
            extensions: Int = 0,
            bookDictionaries: Int = 0,
            customDictionaries: Int = 0,
            sharedDictionaries: Int = 0
        ) {
            self.books = books
            self.chapters = chapters
            self.cachedChapters = cachedChapters
            self.repositories = repositories
            self.extensions = extensions
            self.bookDictionaries = bookDictionaries
            self.customDictionaries = customDictionaries
            self.sharedDictionaries = sharedDictionaries
        }
    }

    public let schemaVersion: Int
    public let appVersion: String
    public let createdAt: Date
    public let scopes: [BackupScope]
    public let counts: Counts

    public init(
        schemaVersion: Int = BackupManifest.currentSchemaVersion,
        appVersion: String,
        createdAt: Date,
        scopes: [BackupScope],
        counts: Counts
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.scopes = scopes
        self.counts = counts
    }

    /// Nhóm có trong file này, theo thứ tự hiển thị.
    public var availableScopes: [BackupScope] {
        let present = Set(scopes)
        return BackupScope.displayOrder.filter { present.contains($0) }
    }

    public var isSupported: Bool {
        schemaVersion <= BackupManifest.currentSchemaVersion
    }

    public static var runningAppVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (version?, buildNumber?): return "\(version) (\(buildNumber))"
        case let (version?, nil): return version
        case let (nil, buildNumber?): return buildNumber
        default: return "unknown"
        }
    }
}
