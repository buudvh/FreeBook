import Foundation
import SwiftData

/// Đọc thư viện SwiftData thành DTO `Sendable` để worker nén ngoài MainActor dùng lại.
/// Chỉ đọc — không `insert/delete/save` bất cứ gì.
@MainActor
public struct BackupLibraryReader {
    /// Toàn bộ dữ liệu SwiftData cần cho một archive, đã tách khỏi `@Model`.
    public struct Payload: Sendable {
        public var books: [BackupPayload.BookRecord]
        public var collections: [BackupPayload.CollectionRecord]
        public var repositories: [BackupPayload.RepositoryRecord]
        public var extensions: [BackupPayload.ExtensionRecord]
        /// bookId của các truyện có thư mục từ điển riêng nhưng không còn trong thư viện —
        /// vẫn phải sao lưu vì người dùng yêu cầu "vp/name riêng của tất cả truyện".
        public var orphanDictionaryBookIds: [String]

        public init(
            books: [BackupPayload.BookRecord],
            collections: [BackupPayload.CollectionRecord] = [],
            repositories: [BackupPayload.RepositoryRecord],
            extensions: [BackupPayload.ExtensionRecord],
            orphanDictionaryBookIds: [String]
        ) {
            self.books = books
            self.collections = collections
            self.repositories = repositories
            self.extensions = extensions
            self.orphanDictionaryBookIds = orphanDictionaryBookIds
        }
    }

    private let context: ModelContext

    /// Dùng `ModelContext` mới trên cùng container để không đụng context của View.
    public init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    public func read(scopes: Set<BackupScope>) -> Payload {
        let books = readBooks()
        let bookIds = Set(books.map { $0.bookId })
        let includeExtensions = scopes.contains(.extensions)

        return Payload(
            books: books,
            collections: readCollections(),
            repositories: includeExtensions ? readRepositories() : [],
            extensions: includeExtensions ? readExtensions() : [],
            orphanDictionaryBookIds: scopes.contains(.dictBooks)
                ? BackupLibraryReader.dictionaryBookIds().filter { !bookIds.contains($0) }
                : []
        )
    }

    private func readBooks() -> [BackupPayload.BookRecord] {
        let descriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\.bookId)])
        guard let rows = try? context.fetch(descriptor) else { return [] }
        return rows.map { book in
            BackupPayload.BookRecord(
                bookId: book.bookId,
                title: book.title,
                author: book.author,
                coverUrl: book.coverUrl,
                desc: book.desc,
                detailUrl: book.detailUrl,
                sourceName: book.sourceName,
                sourceUrl: book.sourceUrl,
                extensionPackageId: book.extensionPackageId,
                host: book.host,
                currentChapterIndex: book.currentChapterIndex,
                currentChapterPage: book.currentChapterPage,
                currentChapterTitle: book.currentChapterTitle,
                lastReadDate: book.lastReadDate,
                isOnShelf: book.isOnShelf,
                isHistory: book.isHistory,
                isPinned: book.isPinned
            )
        }
    }

    /// Bộ sưu tập luôn được đọc: nó thuộc nhóm `.books` (nhóm bắt buộc) và chỉ nặng vài KB.
    private func readCollections() -> [BackupPayload.CollectionRecord] {
        let descriptor = FetchDescriptor<BookCollection>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        guard let rows = try? context.fetch(descriptor) else { return [] }
        return rows.map { collection in
            BackupPayload.CollectionRecord(
                collectionId: collection.collectionId,
                name: collection.name,
                sortOrder: collection.sortOrder,
                createdAt: collection.createdAt,
                bookIds: collection.books.map { $0.bookId }.sorted()
            )
        }
    }

    private func readRepositories() -> [BackupPayload.RepositoryRecord] {
        let descriptor = FetchDescriptor<Repository>(sortBy: [SortDescriptor(\.url)])
        guard let rows = try? context.fetch(descriptor) else { return [] }
        return rows.map { repo in
            BackupPayload.RepositoryRecord(
                url: repo.url,
                name: repo.name,
                author: repo.author,
                desc: repo.desc,
                isEnabled: repo.isEnabled
            )
        }
    }

    private func readExtensions() -> [BackupPayload.ExtensionRecord] {
        let descriptor = FetchDescriptor<Extension>(sortBy: [SortDescriptor(\.packageId)])
        guard let rows = try? context.fetch(descriptor) else { return [] }
        let root = ExtensionManager.shared.extensionsDirectory.standardized.path
        return rows.map { ext in
            BackupPayload.ExtensionRecord(
                packageId: ext.packageId,
                name: ext.name,
                author: ext.author,
                version: ext.version,
                sourceUrl: ext.sourceUrl,
                iconUrl: ext.iconUrl,
                desc: ext.desc,
                type: ext.type,
                locale: ext.locale,
                downloadUrl: ext.downloadUrl,
                configJson: ext.configJson,
                isEnabled: ext.isEnabled,
                isPinned: ext.isPinned,
                repositoryUrl: ext.repository?.url,
                localPathRelative: BackupLibraryReader.relativePath(of: ext.localPath, under: root)
            )
        }
    }

    /// `Extension.localPath` là đường dẫn tuyệt đối của máy tạo backup. Giữ phần đuôi tính từ
    /// `extensions/` để máy khác dựng lại được, còn phần sandbox prefix thì bỏ.
    private static func relativePath(of localPath: String, under root: String) -> String {
        guard !localPath.isEmpty else { return "" }
        let standardized = URL(fileURLWithPath: localPath).standardized.path
        guard standardized.hasPrefix(root) else { return "" }
        let suffix = String(standardized.dropFirst(root.count))
        return suffix.hasPrefix("/") ? String(suffix.dropFirst()) : suffix
    }

    /// Các bookId đang có thư mục `translate/books/<bookId>/`.
    public static func dictionaryBookIds() -> [String] {
        let booksRoot = TranslationManager.shared.translateDirectory.appendingPathComponent("books", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: booksRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.lastPathComponent }
            .sorted()
    }
}
