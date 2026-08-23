import Foundation
import SwiftData

/// Đọc file `.fbbackup` rồi **gộp** vào dữ liệu đang có. Không xoá, không ghi đè cái local đã có:
/// truyện/kho/ext trùng thì giữ bản của máy, chỉ thêm phần thiếu.
///
/// Chia hai pha để UI kịp hỏi lại người dùng: `prepare` giải nén + đọc `manifest.json`, còn
/// `restore()` mới thật sự ghi. Người gọi chịu trách nhiệm `cleanUp()` thư mục tạm.
public actor BackupRestoreWorker {
    public struct Prepared: Sendable {
        public let directory: URL
        public let manifest: BackupManifest
        public let bookIdBySlug: [String: String]

        public func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    public struct Options: Sendable {
        public var scopes: Set<BackupScope>
        public var overwriteSharedDictionaries: Bool

        public init(scopes: Set<BackupScope>, overwriteSharedDictionaries: Bool = false) {
            self.scopes = scopes.union([.books])
            self.overwriteSharedDictionaries = overwriteSharedDictionaries
        }
    }

    public struct Outcome: Sendable {
        public let library: BackupLibraryWriter.Report
        public let chapters: BackupChapterRestorer.Outcome
        public let covers: BackupCoverArchiver.Report
        public let dictionaries: BackupDictionaryRestorer.Report

        public var errors: [String] {
            library.errors + chapters.errors + covers.errors + dictionaries.errors
        }
    }

    public enum Failure: LocalizedError {
        case missingManifest
        case unsupportedSchema(Int)

        public var errorDescription: String? {
            switch self {
            case .missingManifest:
                return "File sao lưu không hợp lệ (thiếu manifest.json)"
            case .unsupportedSchema(let version):
                return "File sao lưu thuộc phiên bản mới hơn (schema \(version)) — hãy cập nhật app"
            }
        }
    }

    private let container: ModelContainer
    private let prepared: Prepared
    private let options: Options
    private let report: @Sendable (BackupProgress) -> Void

    public init(
        container: ModelContainer,
        prepared: Prepared,
        options: Options,
        report: @escaping @Sendable (BackupProgress) -> Void = { _ in }
    ) {
        self.container = container
        self.prepared = prepared
        self.options = options
        self.report = report
    }

    /// Giải nén ra thư mục tạm và đọc manifest. Ném lỗi thì thư mục tạm đã được dọn.
    public static func prepare(archive: URL) throws -> Prepared {
        let staging = try BackupPaths.makeWorkingDirectory(prefix: "fb-backup-restore")
        do {
            try BackupZipArchive.extract(archive: archive, to: staging)
            let decoder = BackupPayload.makeDecoder()

            guard let manifestData = BackupZipArchive.readStaged(entryName: BackupPaths.manifest, in: staging) else {
                throw Failure.missingManifest
            }
            let manifest = try decoder.decode(BackupManifest.self, from: manifestData)
            guard manifest.isSupported else {
                throw Failure.unsupportedSchema(manifest.schemaVersion)
            }

            var bookIdBySlug: [String: String] = [:]
            if let slugData = BackupZipArchive.readStaged(entryName: BackupPaths.slugs, in: staging),
               let entries = try? decoder.decode([BackupPayload.SlugEntry].self, from: slugData) {
                for entry in entries { bookIdBySlug[entry.slug] = entry.bookId }
            }

            return Prepared(directory: staging, manifest: manifest, bookIdBySlug: bookIdBySlug)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    public func restore() async -> Outcome {
        var library = BackupLibraryWriter.Report()
        var chapters = BackupChapterRestorer.Outcome()

        let books = decode([BackupPayload.BookRecord].self, entry: BackupPaths.books) ?? []

        if options.scopes.contains(.extensions) {
            library.merge(await restoreExtensionsAndRepositories())
        }

        report(BackupProgress(phase: .restoringBooks, totalUnits: books.count))
        let capturedContainer = container
        let bookReport = await MainActor.run {
            BackupLibraryWriter(container: capturedContainer).insertMissingBooks(books)
        }
        library.merge(bookReport)

        await restoreChapters(books: books, library: &library, chapters: &chapters)

        report(BackupProgress(phase: .restoringCovers, totalUnits: books.count))
        let covers = BackupCoverArchiver.restore(
            books: books,
            bookIdBySlug: prepared.bookIdBySlug,
            from: prepared.directory
        )

        report(BackupProgress(phase: .restoringDictionaries))
        let dictionaries = BackupDictionaryRestorer.restore(
            from: prepared.directory,
            scopes: options.scopes,
            bookIdBySlug: prepared.bookIdBySlug,
            overwriteShared: options.overwriteSharedDictionaries
        )
        await reloadDictionariesIfNeeded(dictionaries)

        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name("extensionDidUpdate"), object: nil)
        }

        AppLogger.shared.log(
            "♻️ [Restore] \(library.insertedBooks) truyện mới, \(library.skippedBooks) bỏ qua, "
            + "\(chapters.restoredChapters) chương, \(chapters.restoredCachedChapters) chương có nội dung, "
            + "\(covers.restoredCovers) bìa (\(covers.skippedCovers) đã có), "
            + "\(library.insertedRepositories) kho, \(library.upsertedExtensions) ext, "
            + "\(dictionaries.customFiles + dictionaries.bookFiles + dictionaries.sharedFiles) file từ điển"
        )
        report(BackupProgress(phase: .finished))

        return Outcome(library: library, chapters: chapters, covers: covers, dictionaries: dictionaries)
    }

    // MARK: - Các bước

    private func restoreExtensionsAndRepositories() async -> BackupLibraryWriter.Report {
        var outcome = BackupLibraryWriter.Report()
        let repositories = decode([BackupPayload.RepositoryRecord].self, entry: BackupPaths.repositories) ?? []
        let extensions = decode([BackupPayload.ExtensionRecord].self, entry: BackupPaths.extensions) ?? []

        report(BackupProgress(phase: .restoringRepositories, totalUnits: repositories.count))
        let capturedContainer = container
        let existingVersions = await MainActor.run {
            BackupLibraryWriter(container: capturedContainer).existingExtensionVersions()
        }

        report(BackupProgress(phase: .restoringExtensions, totalUnits: extensions.count))
        let installed = BackupExtensionInstaller.install(
            from: prepared.directory,
            records: extensions,
            existingVersions: existingVersions
        )
        outcome.errors.append(contentsOf: installed.errors)

        let commands = installed.commands
        let batch = await MainActor.run { () -> BackupLibraryWriter.Report in
            let writer = BackupLibraryWriter(container: capturedContainer)
            var result = writer.insertMissingRepositories(repositories)
            result.merge(writer.upsertExtensions(commands))
            return result
        }
        outcome.merge(batch)
        return outcome
    }

    private func restoreChapters(
        books: [BackupPayload.BookRecord],
        library: inout BackupLibraryWriter.Report,
        chapters: inout BackupChapterRestorer.Outcome
    ) async {
        var slugByBookId: [String: String] = [:]
        for (slug, bookId) in prepared.bookIdBySlug { slugByBookId[bookId] = slug }
        let capturedContainer = container

        for (index, book) in books.enumerated() {
            report(BackupProgress(
                phase: .restoringChapters,
                completedUnits: index,
                totalUnits: books.count,
                detail: book.title
            ))
            guard let slug = slugByBookId[book.bookId],
                  let records = decode([BackupPayload.ChapterRecord].self, entry: BackupPaths.chapters(slug: slug)),
                  !records.isEmpty
            else { continue }

            let contentURL = options.scopes.contains(.content)
                ? BackupZipArchive.stagedURL(entryName: BackupPaths.content(slug: slug), in: prepared.directory)
                : nil

            let outcome = await BackupChapterRestorer.restore(
                bookId: book.bookId,
                title: book.title,
                records: records,
                contentFileURL: contentURL
            )
            chapters.merge(outcome)

            guard ChapterStoreConfiguration.enableSwiftDataTOCWrite else { continue }
            let bookId = book.bookId
            let keepsCacheMetadata = outcome.keptOffsets
            let mirrored = await MainActor.run {
                BackupLibraryWriter(container: capturedContainer).mirrorChapters(
                    bookId: bookId,
                    records: records,
                    keepsCacheMetadata: keepsCacheMetadata
                )
            }
            library.merge(mirrored)
        }
    }

    private func reloadDictionariesIfNeeded(_ dictionaries: BackupDictionaryRestorer.Report) async {
        let touched = dictionaries.customFiles + dictionaries.bookFiles + dictionaries.sharedFiles
        guard touched > 0 else { return }
        do {
            try await TranslationManager.shared.loadAllDictionaries()
        } catch {
            AppLogger.shared.log("⚠️ [Restore] Nạp lại từ điển thất bại: \(error.localizedDescription)")
        }
        TranslationManager.shared.notifyDictionariesDidUpdate()
    }

    private func decode<T: Decodable>(_ type: T.Type, entry: String) -> T? {
        guard let data = BackupZipArchive.readStaged(entryName: entry, in: prepared.directory) else { return nil }
        return try? BackupPayload.makeDecoder().decode(T.self, from: data)
    }
}
