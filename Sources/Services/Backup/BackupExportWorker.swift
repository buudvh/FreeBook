import Foundation
import SwiftData

/// Dựng file `.fbbackup`. Chạy ngoài MainActor; chỉ nhảy vào MainActor đúng một lần để đọc
/// thư viện SwiftData thành DTO.
public actor BackupExportWorker {
    public struct Outcome: Sendable {
        public let fileURL: URL
        public let manifest: BackupManifest
    }

    private let container: ModelContainer
    private let scopes: Set<BackupScope>
    private let report: @Sendable (BackupProgress) -> Void

    public init(
        container: ModelContainer,
        scopes: Set<BackupScope>,
        report: @escaping @Sendable (BackupProgress) -> Void = { _ in }
    ) {
        self.container = container
        self.scopes = scopes.union([.books])
        self.report = report
    }

    public func export(destination: URL? = nil) async throws -> Outcome {
        let staging = try BackupPaths.makeWorkingDirectory(prefix: "fb-backup-export")
        defer { try? FileManager.default.removeItem(at: staging) }

        report(BackupProgress(phase: .readingLibrary))
        let capturedContainer = container
        let capturedScopes = scopes
        let payload = await MainActor.run {
            BackupLibraryReader(container: capturedContainer).read(scopes: capturedScopes)
        }

        let encoder = BackupPayload.makeEncoder()
        var counts = BackupManifest.Counts()
        counts.books = payload.books.count
        counts.repositories = payload.repositories.count
        counts.extensions = payload.extensions.count

        let slugByBookId = makeSlugTable(payload: payload)
        try stageLibrary(payload: payload, slugByBookId: slugByBookId, encoder: encoder, into: staging)

        let chapterTotals = try await stageChapters(
            books: payload.books,
            slugByBookId: slugByBookId,
            encoder: encoder,
            into: staging
        )
        counts.chapters = chapterTotals.chapters
        counts.cachedChapters = chapterTotals.cached

        // Nhóm `.content` bật thì gom nội dung mọi truyện. Tắt thì vẫn phải gom nội dung của truyện
        // local/TXT: loại này không có nguồn online để tải lại, mất file `.bin` là mất luôn nội dung.
        let contentBooks = scopes.contains(.content)
            ? payload.books
            : payload.books.filter { $0.isLocalBook }
        if !contentBooks.isEmpty {
            if !scopes.contains(.content) {
                AppLogger.shared.log("💾 [Backup] Không chọn nhóm nội dung — vẫn sao lưu nội dung của \(contentBooks.count) truyện local/TXT")
            }
            try await stageContent(books: contentBooks, slugByBookId: slugByBookId, into: staging)
        }

        report(BackupProgress(phase: .copyingCovers))
        counts.covers = try BackupCoverArchiver.stage(
            books: payload.books,
            slugByBookId: slugByBookId,
            into: staging
        )

        if scopes.contains(.extensions) {
            try stageExtensionFolders(records: payload.extensions, into: staging)
        }

        report(BackupProgress(phase: .copyingDictionaries))
        let dictSummary = try BackupDictionaryArchiver.stage(
            scopes: scopes,
            slugByBookId: slugByBookId,
            into: staging
        )
        counts.customDictionaries = dictSummary.customFiles
        counts.bookDictionaries = dictSummary.bookFolders
        counts.sharedDictionaries = dictSummary.sharedFiles

        // Cài đặt & cấu hình luôn đi kèm, không phụ thuộc nhóm nào (chỉ vài KB) — phía khôi phục mới
        // hỏi người dùng có ghi vào máy hay không.
        counts.settings = try BackupSettingsArchiver.stage(into: staging)

        let manifest = BackupManifest(
            appVersion: BackupManifest.runningAppVersion,
            createdAt: Date(),
            scopes: BackupScope.displayOrder.filter { scopes.contains($0) },
            counts: counts
        )
        try BackupZipArchive.stage(
            data: try encoder.encode(manifest),
            entryName: BackupPaths.manifest,
            in: staging
        )

        report(BackupProgress(phase: .compressing, detail: "Đang tạo file .fbbackup"))
        let target = destination ?? BackupPaths.backupsDirectory
            .appendingPathComponent(BackupPaths.makeBackupFileName())
        try BackupZipArchive.makeArchive(from: staging, to: target)

        let size = ByteCountFormatter.string(fromByteCount: BackupPaths.fileSize(at: target), countStyle: .file)
        AppLogger.shared.log("💾 [Backup] Đã tạo \(target.lastPathComponent) — \(size), \(counts.books) truyện, \(counts.chapters) chương, \(counts.covers) bìa")
        report(BackupProgress(phase: .finished, detail: size))
        return Outcome(fileURL: target, manifest: manifest)
    }

    // MARK: - Các bước

    /// Slug cấp cho mọi bookId có thể xuất hiện trong archive, kể cả truyện chỉ còn từ điển riêng.
    private func makeSlugTable(payload: BackupLibraryReader.Payload) -> [String: String] {
        var table: [String: String] = [:]
        let ids = payload.books.map { $0.bookId } + payload.orphanDictionaryBookIds
        for (index, bookId) in ids.enumerated() where table[bookId] == nil {
            table[bookId] = BackupPayload.slug(forIndex: index)
        }
        return table
    }

    private func stageLibrary(
        payload: BackupLibraryReader.Payload,
        slugByBookId: [String: String],
        encoder: JSONEncoder,
        into staging: URL
    ) throws {
        let slugs = slugByBookId
            .map { BackupPayload.SlugEntry(slug: $0.value, bookId: $0.key) }
            .sorted { $0.slug < $1.slug }

        try BackupZipArchive.stage(data: try encoder.encode(slugs), entryName: BackupPaths.slugs, in: staging)
        try BackupZipArchive.stage(data: try encoder.encode(payload.books), entryName: BackupPaths.books, in: staging)

        guard scopes.contains(.extensions) else { return }
        try BackupZipArchive.stage(
            data: try encoder.encode(payload.repositories),
            entryName: BackupPaths.repositories,
            in: staging
        )
        try BackupZipArchive.stage(
            data: try encoder.encode(payload.extensions),
            entryName: BackupPaths.extensions,
            in: staging
        )
    }

    private func stageChapters(
        books: [BackupPayload.BookRecord],
        slugByBookId: [String: String],
        encoder: JSONEncoder,
        into staging: URL
    ) async throws -> (chapters: Int, cached: Int) {
        var chapters = 0
        var cached = 0

        for (index, book) in books.enumerated() {
            report(BackupProgress(
                phase: .writingChapters,
                completedUnits: index,
                totalUnits: books.count,
                detail: book.title
            ))
            guard let slug = slugByBookId[book.bookId] else { continue }
            let toc = (try? await ChapterStore.shared.fetchOrderedTOC(bookId: book.bookId)) ?? []
            guard !toc.isEmpty else { continue }

            let records = toc.map { snapshot in
                BackupPayload.ChapterRecord(
                    index: snapshot.index,
                    title: snapshot.title,
                    url: snapshot.url,
                    host: snapshot.host,
                    titleTrans: snapshot.titleTrans,
                    isCached: snapshot.isCached,
                    offset: snapshot.offset,
                    length: snapshot.length,
                    updatedAt: snapshot.updatedAt
                )
            }
            chapters += records.count
            cached += records.reduce(0) { $0 + ($1.isCached ? 1 : 0) }
            try BackupZipArchive.stage(
                data: try encoder.encode(records),
                entryName: BackupPaths.chapters(slug: slug),
                in: staging
            )
        }

        return (chapters, cached)
    }

    private func stageContent(
        books: [BackupPayload.BookRecord],
        slugByBookId: [String: String],
        into staging: URL
    ) async throws {
        for (index, book) in books.enumerated() {
            report(BackupProgress(
                phase: .copyingContent,
                completedUnits: index,
                totalUnits: books.count,
                detail: book.title
            ))
            guard let slug = slugByBookId[book.bookId] else { continue }
            let binURL = await BookBinManager.shared.binFilePath(for: book.bookId)
            guard FileManager.default.fileExists(atPath: binURL.path) else { continue }
            try BackupZipArchive.stage(
                fileAt: binURL,
                entryName: BackupPaths.content(slug: slug),
                in: staging
            )
        }
    }

    private func stageExtensionFolders(records: [BackupPayload.ExtensionRecord], into staging: URL) throws {
        let root = ExtensionManager.shared.extensionsDirectory
        for (index, record) in records.enumerated() {
            report(BackupProgress(
                phase: .copyingExtensions,
                completedUnits: index,
                totalUnits: records.count,
                detail: record.name
            ))
            let folder = root.appendingPathComponent(record.packageId, isDirectory: true)
            guard BackupExportWorker.isDirectory(folder) else { continue }
            try BackupZipArchive.stage(
                directoryAt: folder,
                entryName: BackupPaths.extensionFolder(packageId: record.packageId),
                in: staging
            )
        }

        let common = root.appendingPathComponent(BackupPaths.extensionCommonFolderName, isDirectory: true)
        if BackupExportWorker.isDirectory(common) {
            try BackupZipArchive.stage(
                directoryAt: common,
                entryName: BackupPaths.extensionCommonFolder,
                in: staging
            )
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
