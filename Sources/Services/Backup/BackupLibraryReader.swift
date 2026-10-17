import Foundation
import SwiftData

/// Đọc thư viện thành DTO `Sendable` để worker nén ngoài MainActor dùng lại.
/// Chỉ đọc — không `insert/delete/save` bất cứ gì.
///
/// Không gắn `@MainActor`: sách/bộ sưu tập đọc bằng `ModelContext` riêng; tiện ích, kho và `localStorage`
/// đọc qua bảng chụp `nonisolated` của `ExtensionLibraryRepository` / `ExtensionLocalStorageStore`. Nhờ vậy
/// `BackupExportWorker` gọi thẳng trên actor của nó — đọc cả thư viện không chặn main thread. Context không
/// được thoát khỏi `read(scopes:)`.
public struct BackupLibraryReader {
    /// Toàn bộ dữ liệu cần cho một archive, đã tách khỏi `@Model`.
    public struct Payload: Sendable {
        public var books: [BackupPayload.BookRecord]
        public var collections: [BackupPayload.CollectionRecord]
        public var repositories: [BackupPayload.RepositoryRecord]
        public var extensions: [BackupPayload.ExtensionRecord]
        /// `[packageId: [key: value]]` — chỉ namespace của tiện ích có trong `extensions`.
        public var extensionLocalStorage: [String: [String: String]]
        /// bookId của các truyện có thư mục từ điển riêng nhưng không còn trong thư viện —
        /// vẫn phải sao lưu vì người dùng yêu cầu "vp/name riêng của tất cả truyện".
        public var orphanDictionaryBookIds: [String]

        public init(
            books: [BackupPayload.BookRecord],
            collections: [BackupPayload.CollectionRecord] = [],
            repositories: [BackupPayload.RepositoryRecord],
            extensions: [BackupPayload.ExtensionRecord],
            extensionLocalStorage: [String: [String: String]] = [:],
            orphanDictionaryBookIds: [String]
        ) {
            self.books = books
            self.collections = collections
            self.repositories = repositories
            self.extensions = extensions
            self.extensionLocalStorage = extensionLocalStorage
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
        let extensions = includeExtensions ? readExtensions() : []

        return Payload(
            books: books,
            collections: readCollections(),
            repositories: includeExtensions ? readRepositories() : [],
            extensions: extensions,
            extensionLocalStorage: includeExtensions ? readLocalStorage(for: extensions) : [:],
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

    /// Giữ **thứ tự thêm kho** (không sắp lại): thứ tự này quyết định kho nào thắng khi trùng `packageId`, và
    /// restore thêm kho theo đúng thứ tự trong archive. `isEnabled` không còn — luôn ghi `true` cho app cũ.
    private func readRepositories() -> [BackupPayload.RepositoryRecord] {
        ExtensionLibraryRepository.repositoriesSnapshot().map { repo in
            BackupPayload.RepositoryRecord(
                url: repo.url,
                name: repo.name,
                author: repo.author,
                desc: repo.desc,
                isEnabled: true
            )
        }
    }

    /// Chỉ tiện ích **đã cài** — mục chưa cài của kho nằm ở cache registry, làm mới kho là có lại.
    private func readExtensions() -> [BackupPayload.ExtensionRecord] {
        ExtensionLibraryRepository.installedSnapshot()
            .sorted { $0.packageId < $1.packageId }
            .map { ext in
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
                    isEnabled: true,
                    isPinned: ext.isPinned,
                    repositoryUrl: ext.repositoryUrl,
                    localPathRelative: ext.folder,
                    pinnedAt: ext.pinnedAt,
                    lastUsedAt: ext.lastUsedAt,
                    isNsfw: ext.isNsfw,
                    savesHistory: ext.savesHistory
                )
            }
    }

    /// Namespace `"global"` / `"path:…"` (executor không gắn tiện ích đã cài) không thuộc tiện ích nào nên bỏ.
    private func readLocalStorage(for extensions: [BackupPayload.ExtensionRecord]) -> [String: [String: String]] {
        let packageIds = Set(extensions.map(\.packageId))
        guard !packageIds.isEmpty else { return [:] }
        return ExtensionLocalStorageStore.shared.snapshot().filter { packageIds.contains($0.key) && !$0.value.isEmpty }
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
