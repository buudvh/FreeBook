import Foundation

/// Các bản ghi Codable ghi vào archive. Tất cả là `struct` lồng nhau để giữ đúng một type
/// top-level mỗi file, và tất cả đều `Sendable` để đi qua ranh giới actor của worker.
public enum BackupPayload {
    /// Bảng tra `slug` ⇄ `bookId`. Dùng slug (`b0001`) làm tên entry vì `bookId` có thể chứa
    /// ký tự đường dẫn, và để không phụ thuộc hàm sha256 private của từng owner file.
    public struct SlugEntry: Codable, Sendable {
        public let slug: String
        public let bookId: String

        public init(slug: String, bookId: String) {
            self.slug = slug
            self.bookId = bookId
        }
    }

    public struct BookRecord: Codable, Sendable {
        public let bookId: String
        public let title: String
        public let author: String
        public let coverUrl: String
        public let desc: String
        public let detailUrl: String
        public let sourceName: String
        public let sourceUrl: String
        public let extensionPackageId: String
        public let host: String?
        public let currentChapterIndex: Int
        public let currentChapterPage: Int
        public let currentChapterTitle: String
        public let lastReadDate: Date
        public let isOnShelf: Bool
        public let isHistory: Bool
        /// `Optional` **có chủ đích**: `init(from:)` tổng hợp của Swift không dùng giá trị mặc định
        /// của thuộc tính, nên khoá mới phải là optional để archive tạo trước 1.3.328 còn decode được.
        public let isPinned: Bool?

        public init(
            bookId: String,
            title: String,
            author: String,
            coverUrl: String,
            desc: String,
            detailUrl: String,
            sourceName: String,
            sourceUrl: String,
            extensionPackageId: String,
            host: String?,
            currentChapterIndex: Int,
            currentChapterPage: Int,
            currentChapterTitle: String,
            lastReadDate: Date,
            isOnShelf: Bool,
            isHistory: Bool,
            isPinned: Bool? = nil
        ) {
            self.bookId = bookId
            self.title = title
            self.author = author
            self.coverUrl = coverUrl
            self.desc = desc
            self.detailUrl = detailUrl
            self.sourceName = sourceName
            self.sourceUrl = sourceUrl
            self.extensionPackageId = extensionPackageId
            self.host = host
            self.currentChapterIndex = currentChapterIndex
            self.currentChapterPage = currentChapterPage
            self.currentChapterTitle = currentChapterTitle
            self.lastReadDate = lastReadDate
            self.isOnShelf = isOnShelf
            self.isHistory = isHistory
            self.isPinned = isPinned
        }

        /// `true` khi truyện được nhập từ file trong máy (TXT/EPUB) — không có nguồn online để tải
        /// lại nội dung, nên nội dung chương của nhóm này phải luôn nằm trong archive dù người dùng
        /// tắt nhóm `.content`.
        ///
        /// **Phải khớp đúng logic `Book.isLocalBook`** (`Sources/Models/Database/Book.swift`) — sửa
        /// một bên thì sửa cả bên kia, nếu không backup và app sẽ hiểu khác nhau về "truyện local".
        public var isLocalBook: Bool {
            extensionPackageId.lowercased() == "local"
                || detailUrl.lowercased().hasPrefix("local://")
                || sourceUrl.lowercased().hasPrefix("local://")
                || sourceName.lowercased() == "local"
        }

        /// `true` khi bìa **không** tải lại được từ mạng — đúng trường hợp truyện nhập từ file:
        /// `ImageCacheManager` giữ file JPEG trong `covers/` còn `coverUrl` để rỗng. Chỉ nhóm này
        /// mới cần gom ảnh bìa vào archive.
        public var hasUnrecoverableCover: Bool {
            let url = coverUrl.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !url.hasPrefix("http://") && !url.hasPrefix("https://")
        }
    }

    /// Một bộ sưu tập và danh sách `bookId` thành viên. Quan hệ N-N được ghi **ở phía bộ sưu tập** để
    /// khôi phục chỉ cần một vòng: tạo bộ (hoặc dùng bộ trùng tên đã có) rồi gắn các truyện có mặt.
    public struct CollectionRecord: Codable, Sendable {
        public let collectionId: String
        public let name: String
        public let sortOrder: Int
        public let createdAt: Date
        public let bookIds: [String]

        public init(collectionId: String, name: String, sortOrder: Int, createdAt: Date, bookIds: [String]) {
            self.collectionId = collectionId
            self.name = name
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.bookIds = bookIds
        }
    }

    public struct RepositoryRecord: Codable, Sendable {
        public let url: String
        public let name: String
        public let author: String?
        public let desc: String?
        public let isEnabled: Bool

        public init(url: String, name: String, author: String?, desc: String?, isEnabled: Bool) {
            self.url = url
            self.name = name
            self.author = author
            self.desc = desc
            self.isEnabled = isEnabled
        }
    }

    public struct ExtensionRecord: Codable, Sendable {
        public let packageId: String
        public let name: String
        public let author: String
        public let version: Int
        public let sourceUrl: String
        public let iconUrl: String?
        public let desc: String?
        public let type: String
        public let locale: String
        public let downloadUrl: String
        public let configJson: String
        public let isEnabled: Bool
        public let isPinned: Bool
        public let repositoryUrl: String?
        /// `Extension.localPath` bỏ tiền tố `extensions/`. `localPath` gốc là đường dẫn tuyệt đối
        /// của máy tạo backup nên không dùng lại được — khi restore phải tính lại.
        public let localPathRelative: String

        public init(
            packageId: String,
            name: String,
            author: String,
            version: Int,
            sourceUrl: String,
            iconUrl: String?,
            desc: String?,
            type: String,
            locale: String,
            downloadUrl: String,
            configJson: String,
            isEnabled: Bool,
            isPinned: Bool,
            repositoryUrl: String?,
            localPathRelative: String
        ) {
            self.packageId = packageId
            self.name = name
            self.author = author
            self.version = version
            self.sourceUrl = sourceUrl
            self.iconUrl = iconUrl
            self.desc = desc
            self.type = type
            self.locale = locale
            self.downloadUrl = downloadUrl
            self.configJson = configJson
            self.isEnabled = isEnabled
            self.isPinned = isPinned
            self.repositoryUrl = repositoryUrl
            self.localPathRelative = localPathRelative
        }
    }

    /// Một chương trong `chapters/<slug>.json`. `offset`/`length` chỉ có nghĩa khi đi cùng
    /// đúng file `content/<slug>.bin` của cùng archive.
    public struct ChapterRecord: Codable, Sendable {
        public let index: Int
        public let title: String
        public let url: String
        public let host: String?
        public let titleTrans: String?
        public let isCached: Bool
        public let offset: Int64
        public let length: Int64
        public let updatedAt: Date

        public init(
            index: Int,
            title: String,
            url: String,
            host: String?,
            titleTrans: String?,
            isCached: Bool,
            offset: Int64,
            length: Int64,
            updatedAt: Date
        ) {
            self.index = index
            self.title = title
            self.url = url
            self.host = host
            self.titleTrans = titleTrans
            self.isCached = isCached
            self.offset = offset
            self.length = length
            self.updatedAt = updatedAt
        }
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Slug ổn định theo thứ tự sách trong backup: `b0001`, `b0002`…
    public static func slug(forIndex index: Int) -> String {
        String(format: "b%04d", index + 1)
    }
}
