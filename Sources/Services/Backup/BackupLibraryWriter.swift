import Foundation
import SwiftData

/// Ghi phần thư viện của một lần khôi phục. Mọi ghi đi qua coordinator + Command DTO: sách qua
/// `BookTransactionCoordinator` (SwiftData), tiện ích/kho qua `ExtensionTransactionCoordinator` (extension store
/// JSON). Writer chỉ tự đọc để biết cái gì đã có (restore là **gộp**, không ghi đè).
@MainActor
public struct BackupLibraryWriter {
    public struct Report: Sendable {
        public var insertedRepositories = 0
        public var upsertedExtensions = 0
        public var restoredExtensionPins = 0
        public var restoredLocalStorageNamespaces = 0
        public var insertedBooks = 0
        public var skippedBooks = 0
        public var mirroredChapters = 0
        public var insertedCollections = 0
        public var errors: [String] = []

        public mutating func merge(_ other: Report) {
            insertedRepositories += other.insertedRepositories
            upsertedExtensions += other.upsertedExtensions
            restoredExtensionPins += other.restoredExtensionPins
            restoredLocalStorageNamespaces += other.restoredLocalStorageNamespaces
            insertedBooks += other.insertedBooks
            skippedBooks += other.skippedBooks
            mirroredChapters += other.mirroredChapters
            insertedCollections += other.insertedCollections
            errors.append(contentsOf: other.errors)
        }
    }

    private let context: ModelContext

    public init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    // MARK: - Đọc trạng thái hiện có

    public func existingRepositoryUrls() -> Set<String> {
        Set(ExtensionLibraryRepository.shared.repositories.map(\.url))
    }

    public func existingBookIds() -> Set<String> {
        let rows = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        return Set(rows.map { $0.bookId })
    }

    /// packageId → version đang cài. Dùng để chỉ thay file extension khi bản trong backup mới hơn.
    /// `nonisolated`: đọc bảng chụp của repository, worker gọi thẳng không cần nhảy lên MainActor.
    nonisolated public static func existingExtensionVersions() -> [String: Int] {
        var table: [String: Int] = [:]
        for ext in ExtensionLibraryRepository.installedSnapshot() { table[ext.packageId] = ext.version }
        return table
    }

    // MARK: - Ghi

    /// Phải chạy **trước** `upsertExtensions`: coordinator chỉ nhận `repositoryUrl` của kho đã tồn tại.
    /// `addRepository` tự bỏ qua kho đã có; lọc trước chỉ để đếm đúng số kho thêm mới. Thêm theo đúng thứ tự
    /// trong archive — thứ tự kho quyết định kho nào thắng khi trùng `packageId`.
    public func insertMissingRepositories(_ records: [BackupPayload.RepositoryRecord]) -> Report {
        var report = Report()
        var existing = existingRepositoryUrls()
        for record in records {
            let url = record.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, !existing.contains(url) else { continue }
            switch ExtensionTransactionCoordinator.shared.addRepository(url: url, name: record.name) {
            case .success:
                existing.insert(url)
                report.insertedRepositories += 1
            case .failure(let error):
                report.errors.append("Kho \(record.url): \(error.localizedDescription)")
            }
        }
        return report
    }

    public func upsertExtensions(_ commands: [UpsertExtensionCommand]) -> Report {
        var report = Report()
        guard !commands.isEmpty else { return report }
        switch ExtensionTransactionCoordinator.shared.upsertExtensions(commands: commands) {
        case .success:
            report.upsertedExtensions = commands.count
        case .failure(let error):
            report.errors.append("Extension: \(error.localizedDescription)")
        }
        return report
    }

    /// Ghim lại tiện ích mà lượt khôi phục **vừa cài thêm** (máy chưa có trước đó) — cùng nguyên tắc ghim truyện
    /// ở `insertMissingBooks`: không đè lựa chọn ghim của máy đang khôi phục.
    ///
    /// Coordinator chưa có API đặt `pinnedAt` theo mốc cho trước nên dùng `togglePinned` (mốc = lúc khôi phục),
    /// gọi lần lượt theo `pinnedAt` gốc để giữ thứ tự ghim; archive cũ chỉ có `isPinned` thì theo tên.
    /// `lastUsedAt` của archive chưa được áp (không có API) — chỉ ảnh hưởng thứ tự "vừa dùng".
    public func restorePins(_ records: [BackupPayload.ExtensionRecord], newlyInstalled: Set<String>) -> Report {
        var report = Report()
        let library = ExtensionLibraryRepository.shared
        let candidates = records
            .filter { $0.wasPinned && newlyInstalled.contains($0.packageId) }
            .sorted { ($0.pinnedAt ?? .distantFuture, $0.name) < ($1.pinnedAt ?? .distantFuture, $1.name) }
        for record in candidates {
            guard let ext = library.installedExtension(packageId: record.packageId), !ext.isPinned else { continue }
            switch ExtensionTransactionCoordinator.shared.togglePinned(packageId: record.packageId) {
            case .success:
                report.restoredExtensionPins += 1
            case .failure(let error):
                report.errors.append("Ghim \(record.name): \(error.localizedDescription)")
            }
        }
        return report
    }

    /// Áp công tắc "Lưu lịch sử đọc/xem" (`savesHistory`) của archive cho tiện ích **đang cài** mà máy này chưa chọn
    /// (`savesHistory == nil`) — không đè lựa chọn của máy đang khôi phục. Phải chạy **sau** `upsertExtensions`:
    /// `UpsertExtensionCommand` không mang trường này. `isNsfw` không cần áp: upsert đọc lại từ `plugin.json`/registry.
    public func restoreHistoryPreferences(_ records: [BackupPayload.ExtensionRecord]) -> Report {
        var report = Report()
        let library = ExtensionLibraryRepository.shared
        for record in records {
            guard let ext = library.installedExtension(packageId: record.packageId) else { continue }
            if let savesHistory = record.savesHistory, ext.savesHistory == nil,
               case .failure(let error) = ExtensionTransactionCoordinator.shared.setSavesHistory(
                   packageId: record.packageId, savesHistory
               ) {
                report.errors.append("Lưu lịch sử \(record.name): \(error.localizedDescription)")
            }
            // Đánh dấu 18+ của người dùng: cùng luật — chỉ áp khi máy này chưa tự chọn.
            if let nsfwOverride = record.nsfwOverride, ext.nsfwOverride == nil,
               case .failure(let error) = ExtensionTransactionCoordinator.shared.setNsfwOverride(
                   packageId: record.packageId, nsfwOverride
               ) {
                report.errors.append("Đánh dấu 18+ \(record.name): \(error.localizedDescription)")
            }
            // Chặn quảng cáo / chế độ máy tính của webview tiện ích: cùng luật — chỉ áp khi máy này chưa tự chọn.
            if let adBlock = record.adBlockOverride, ext.adBlockOverride == nil,
               case .failure(let error) = ExtensionTransactionCoordinator.shared.setAdBlockOverride(
                   packageId: record.packageId, adBlock
               ) {
                report.errors.append("Chặn quảng cáo \(record.name): \(error.localizedDescription)")
            }
            if let desktop = record.desktopModeOverride, ext.desktopModeOverride == nil,
               case .failure(let error) = ExtensionTransactionCoordinator.shared.setDesktopModeOverride(
                   packageId: record.packageId, desktop
               ) {
                report.errors.append("Chế độ máy tính \(record.name): \(error.localizedDescription)")
            }
            if let translate = record.translateOverride, ext.translateOverride == nil,
               case .failure(let error) = ExtensionTransactionCoordinator.shared.setTranslateOverride(
                   packageId: record.packageId, translate
               ) {
                report.errors.append("Tự dịch trang \(record.name): \(error.localizedDescription)")
            }
        }
        return report
    }

    /// Chỉ thêm truyện chưa có. Truyện đã có giữ nguyên metadata **và tiến độ đọc** của máy này.
    ///
    /// Truyện mới nhận lại `lastReadDate` từ bản sao lưu (qua `AddBookToShelfCommand.lastReadDate`)
    /// để kệ sách — vốn sắp theo `lastReadDate` giảm dần — giữ đúng thứ tự đọc của máy nguồn.
    public func insertMissingBooks(_ records: [BackupPayload.BookRecord]) -> Report {
        var report = Report()
        let existing = existingBookIds()

        for record in records {
            guard !existing.contains(record.bookId) else {
                report.skippedBooks += 1
                continue
            }

            let addResult = BookTransactionCoordinator.shared.addBookToShelf(
                command: Self.shelfCommand(for: record),
                in: context
            )

            switch addResult {
            case .success:
                report.insertedBooks += 1
                // Ghim là lựa chọn của người dùng ở máy nguồn; chỉ áp cho truyện **mới thêm** để
                // không đè trạng thái ghim của máy đang khôi phục.
                if record.isPinned == true, record.isOnShelf {
                    let pinResult = BookTransactionCoordinator.shared.setPinned(
                        bookId: record.bookId,
                        isPinned: true,
                        in: context
                    )
                    if case .failure(let error) = pinResult {
                        report.errors.append("Ghim \(record.title): \(error.localizedDescription)")
                    }
                }
                // `addBookToShelf` không tính `titleTrans`/`authorTrans`, mà kệ sách đọc hai field đó.
                let infoResult = BookTransactionCoordinator.shared.updateBookInfo(
                    command: EditBookInfoCommand(
                        bookId: record.bookId,
                        title: record.title,
                        author: record.author,
                        coverUrl: record.coverUrl
                    ),
                    in: context
                )
                if case .failure(let error) = infoResult {
                    report.errors.append("Tên dịch của \(record.title): \(error.localizedDescription)")
                }
            case .failure(let error):
                report.errors.append("Truyện \(record.title): \(error.localizedDescription)")
            }
        }

        return report
    }

    /// Lệnh thêm truyện dựng từ bản ghi backup. Dùng chung cho đường từng truyện ở trên và đường ghi
    /// theo lô của `BackupRestoreWorker` (`BookTransactionCoordinator.addBooksFromBackup`), để hai đường
    /// không trôi khỏi nhau. `nonisolated` vì worker gọi từ ngoài MainActor.
    nonisolated static func shelfCommand(for record: BackupPayload.BookRecord) -> AddBookToShelfCommand {
        AddBookToShelfCommand(
            bookId: record.bookId,
            title: record.title,
            author: record.author,
            coverUrl: record.coverUrl,
            desc: record.desc,
            detailUrl: record.detailUrl,
            sourceName: record.sourceName,
            sourceUrl: record.sourceUrl,
            extensionPackageId: record.extensionPackageId,
            currentChapterIndex: record.currentChapterIndex,
            currentChapterPage: record.currentChapterPage,
            currentChapterTitle: record.currentChapterTitle,
            isOnShelf: record.isOnShelf,
            isHistory: record.isHistory,
            host: record.host,
            lastReadDate: record.lastReadDate
        )
    }

    /// Khôi phục bộ sưu tập theo kiểu **gộp**: bộ trùng tên (không phân biệt hoa/thường) thì dùng lại
    /// bộ đang có, chỉ bổ sung thành viên; không có thì tạo mới. Chỉ gắn những truyện **thật sự có**
    /// trong máy — `BookCollectionCoordinator.addBook` tự bật `isOnShelf`, giữ đúng bất biến.
    public func restoreCollections(_ records: [BackupPayload.CollectionRecord]) -> Report {
        var report = Report()
        guard !records.isEmpty else { return report }

        let existingBookIds = self.existingBookIds()

        for record in records {
            let existing = (try? context.fetch(FetchDescriptor<BookCollection>())) ?? []
            let matched = existing.first {
                $0.name.compare(record.name, options: .caseInsensitive) == .orderedSame
            }

            let collectionId: String
            if let matched {
                collectionId = matched.collectionId
            } else {
                switch BookCollectionCoordinator.shared.createCollection(name: record.name, in: context) {
                case .success(let created):
                    collectionId = created.collectionId
                    report.insertedCollections += 1
                case .failure(let error):
                    report.errors.append("Bộ sưu tập \(record.name): \(error.localizedDescription)")
                    continue
                }
            }

            for bookId in record.bookIds where existingBookIds.contains(bookId) {
                let result = BookCollectionCoordinator.shared.addBook(
                    bookId: bookId,
                    toCollection: collectionId,
                    in: context
                )
                if case .failure(let error) = result {
                    report.errors.append("Bộ sưu tập \(record.name) ← \(bookId): \(error.localizedDescription)")
                }
            }
        }

        return report
    }

    /// Bản sao mục lục sang bảng SwiftData `Chapter`. Production đặt
    /// `enableSwiftDataTOCWrite = false` nên hàm này thoát ngay — chỉ tồn tại để bản build bật cờ
    /// vẫn thấy chương sau khi khôi phục.
    ///
    /// - Parameter keepsCacheMetadata: chỉ `true` ở nhánh chép nguyên file `.bin`, khi đó
    ///   `offset/length` trong backup còn đúng.
    public func mirrorChapters(
        bookId: String,
        records: [BackupPayload.ChapterRecord],
        keepsCacheMetadata: Bool
    ) -> Report {
        var report = Report()
        guard ChapterStoreConfiguration.enableSwiftDataTOCWrite, !records.isEmpty else { return report }

        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        guard let book = try? context.fetch(descriptor).first else { return report }
        let existingIndices = Set(book.chapters.map { $0.index })

        for record in records where !existingIndices.contains(record.index) {
            let result = BookTransactionCoordinator.shared.insertChapterDTO(
                bookId: bookId,
                title: record.title,
                url: record.url,
                index: record.index,
                isCached: keepsCacheMetadata ? record.isCached : false,
                offset: keepsCacheMetadata ? record.offset : 0,
                length: keepsCacheMetadata ? record.length : 0,
                titleTrans: record.titleTrans,
                in: context
            )
            switch result {
            case .success:
                report.mirroredChapters += 1
            case .failure(let error):
                report.errors.append("Chương \(record.index) của \(bookId): \(error.localizedDescription)")
            }
        }

        return report
    }
}
