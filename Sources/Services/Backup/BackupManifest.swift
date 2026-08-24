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
        public var covers: Int
        public var repositories: Int
        public var extensions: Int
        public var bookDictionaries: Int
        public var customDictionaries: Int
        public var sharedDictionaries: Int
        /// Số khoá cài đặt (`settings/user_defaults.plist`). 0 với file tạo trước 1.3.264.
        public var settings: Int
        /// Số file cấu hình rời (`config/*.json`: quy tắc mục lục, công cụ tra cứu nhanh).
        /// 0 với file tạo trước 1.3.265.
        public var config: Int

        public init(
            books: Int = 0,
            chapters: Int = 0,
            cachedChapters: Int = 0,
            covers: Int = 0,
            repositories: Int = 0,
            extensions: Int = 0,
            bookDictionaries: Int = 0,
            customDictionaries: Int = 0,
            sharedDictionaries: Int = 0,
            settings: Int = 0,
            config: Int = 0
        ) {
            self.books = books
            self.chapters = chapters
            self.cachedChapters = cachedChapters
            self.covers = covers
            self.repositories = repositories
            self.extensions = extensions
            self.bookDictionaries = bookDictionaries
            self.customDictionaries = customDictionaries
            self.sharedDictionaries = sharedDictionaries
            self.settings = settings
            self.config = config
        }

        private enum CodingKeys: String, CodingKey {
            case books, chapters, cachedChapters, covers, repositories, extensions
            case bookDictionaries, customDictionaries, sharedDictionaries, settings, config
        }

        /// Viết tay vì `init(from:)` tổng hợp **không** dùng giá trị mặc định của thuộc tính:
        /// thêm khoá mới (`covers`) mà không có decoder này là mọi file `.fbbackup` cũ decode lỗi.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            books = try container.decodeIfPresent(Int.self, forKey: .books) ?? 0
            chapters = try container.decodeIfPresent(Int.self, forKey: .chapters) ?? 0
            cachedChapters = try container.decodeIfPresent(Int.self, forKey: .cachedChapters) ?? 0
            covers = try container.decodeIfPresent(Int.self, forKey: .covers) ?? 0
            repositories = try container.decodeIfPresent(Int.self, forKey: .repositories) ?? 0
            extensions = try container.decodeIfPresent(Int.self, forKey: .extensions) ?? 0
            bookDictionaries = try container.decodeIfPresent(Int.self, forKey: .bookDictionaries) ?? 0
            customDictionaries = try container.decodeIfPresent(Int.self, forKey: .customDictionaries) ?? 0
            sharedDictionaries = try container.decodeIfPresent(Int.self, forKey: .sharedDictionaries) ?? 0
            settings = try container.decodeIfPresent(Int.self, forKey: .settings) ?? 0
            config = try container.decodeIfPresent(Int.self, forKey: .config) ?? 0
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
