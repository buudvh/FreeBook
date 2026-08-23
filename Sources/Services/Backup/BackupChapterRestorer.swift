import Foundation

/// Khôi phục mục lục + nội dung chương cho **một** truyện.
///
/// Hai nhánh khác nhau về bản chất:
/// * Máy chưa có mục lục ⇒ được phép chép nguyên `content/<slug>.bin` vào chỗ thật, nhờ đó
///   `offset/length` trong backup còn hiệu lực và ghi một transaction duy nhất.
/// * Máy đã có mục lục ⇒ **không bao giờ** chép offset qua, vì file `.bin` local đã có nội dung
///   khác ở đúng những offset đó. Nội dung phải được ghi lại rồi ghi nhận offset mới.
public enum BackupChapterRestorer {
    public struct Outcome: Sendable {
        public var restoredChapters = 0
        public var restoredCachedChapters = 0
        /// `true` khi file `.bin` được chép nguyên ⇒ `offset/length` của backup còn dùng được.
        public var keptOffsets = false
        public var errors: [String] = []

        public mutating func merge(_ other: Outcome) {
            restoredChapters += other.restoredChapters
            restoredCachedChapters += other.restoredCachedChapters
            keptOffsets = keptOffsets || other.keptOffsets
            errors.append(contentsOf: other.errors)
        }
    }

    /// - Parameter contentFileURL: `content/<slug>.bin` đã giải nén, `nil` khi người dùng không
    ///   chọn nhóm nội dung hoặc archive không có file đó.
    public static func restore(
        bookId: String,
        title: String,
        records: [BackupPayload.ChapterRecord],
        contentFileURL: URL?
    ) async -> Outcome {
        var outcome = Outcome()
        guard !records.isEmpty else { return outcome }

        let sorted = records.sorted { $0.index < $1.index }
        do {
            let localCount = (try? await ChapterStore.shared.countChapters(bookId: bookId)) ?? 0
            if localCount == 0 {
                try await importFresh(bookId: bookId, records: sorted, contentFileURL: contentFileURL, into: &outcome)
            } else {
                try await mergeIntoExisting(bookId: bookId, records: sorted, contentFileURL: contentFileURL, into: &outcome)
            }
        } catch {
            outcome.errors.append("Chương của \(title): \(error.localizedDescription)")
        }
        return outcome
    }

    // MARK: - Nhánh máy chưa có mục lục

    private static func importFresh(
        bookId: String,
        records: [BackupPayload.ChapterRecord],
        contentFileURL: URL?,
        into outcome: inout Outcome
    ) async throws {
        let keepsOffsets = await installBinFile(bookId: bookId, contentFileURL: contentFileURL, into: &outcome)
        outcome.keptOffsets = keepsOffsets

        let snapshots = records.map { record in
            StoredChapterSnapshot(
                id: Chapter.generateId(bookId: bookId, url: record.url, index: record.index),
                bookId: bookId,
                title: record.title,
                url: record.url,
                index: record.index,
                host: record.host,
                titleTrans: record.titleTrans,
                isCached: keepsOffsets ? record.isCached : false,
                offset: keepsOffsets ? record.offset : 0,
                length: keepsOffsets ? record.length : 0,
                updatedAt: record.updatedAt
            )
        }

        try await ChapterStore.shared.importBookMigration(
            bookId: bookId,
            snapshots: snapshots,
            statusInfo: MigrationStatusInfo(
                bookId: bookId,
                status: "restored",
                schemaVersion: BackupManifest.currentSchemaVersion,
                migratedCount: snapshots.count
            )
        )

        outcome.restoredChapters += snapshots.count
        outcome.restoredCachedChapters += snapshots.reduce(0) { $0 + ($1.isCached ? 1 : 0) }
    }

    /// Chỉ chép `.bin` khi máy **chưa có** file nào cho truyện này; có rồi thì offset trong backup
    /// vô nghĩa và phải bỏ.
    private static func installBinFile(
        bookId: String,
        contentFileURL: URL?,
        into outcome: inout Outcome
    ) async -> Bool {
        guard let contentFileURL, FileManager.default.fileExists(atPath: contentFileURL.path) else { return false }
        let target = await BookBinManager.shared.binFilePath(for: bookId)
        guard !FileManager.default.fileExists(atPath: target.path) else { return false }

        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: contentFileURL, to: target)
            return true
        } catch {
            outcome.errors.append("Nội dung \(bookId): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Nhánh máy đã có mục lục

    private static func mergeIntoExisting(
        bookId: String,
        records: [BackupPayload.ChapterRecord],
        contentFileURL: URL?,
        into outcome: inout Outcome
    ) async throws {
        var localByIndex = try await fetchIndexedTOC(bookId: bookId)

        let missing = records.filter { localByIndex[$0.index] == nil }
        if !missing.isEmpty {
            let metadata = missing.map { record in
                ChapterMetadataSnapshot(
                    title: record.title,
                    url: record.url,
                    index: record.index,
                    host: record.host,
                    titleTrans: record.titleTrans
                )
            }
            _ = try await ChapterStore.shared.upsertPage(bookId: bookId, chapters: metadata)
            outcome.restoredChapters += missing.count
            localByIndex = try await fetchIndexedTOC(bookId: bookId)
        }

        guard let contentFileURL, FileManager.default.fileExists(atPath: contentFileURL.path) else { return }
        let handle = try FileHandle(forReadingFrom: contentFileURL)
        defer { try? handle.close() }

        var processed = 0
        for record in records where record.isCached && record.length > 0 {
            guard let local = localByIndex[record.index], !local.isCached else { continue }
            guard let text = readChunk(handle: handle, offset: record.offset, length: record.length) else { continue }

            let written = try await BookBinManager.shared.writeChapterContent(bookId: bookId, content: text)
            try await ChapterStore.shared.updateCacheMetadata(
                bookId: bookId,
                index: record.index,
                url: local.url,
                isCached: true,
                offset: written.offset,
                length: written.length
            )
            outcome.restoredCachedChapters += 1

            // Chương khôi phục từ sao lưu cũng phải vào chỉ mục tìm toàn văn.
            await ChapterSearchIndex.shared.indexChapter(
                bookId: bookId,
                chapterIndex: record.index,
                chapterUrl: local.url,
                chapterTitle: local.title,
                content: text
            )

            processed += 1
            if processed % 50 == 0 {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
    }

    private static func fetchIndexedTOC(bookId: String) async throws -> [Int: StoredChapterSnapshot] {
        let rows = try await ChapterStore.shared.fetchOrderedTOC(bookId: bookId)
        var table: [Int: StoredChapterSnapshot] = [:]
        for row in rows where table[row.index] == nil { table[row.index] = row }
        return table
    }

    /// Đọc đúng `length` byte tại `offset` — cùng ngữ nghĩa `BookBinManager.readChapterContent`,
    /// chỉ khác là đọc trên file trong archive.
    private static func readChunk(handle: FileHandle, offset: Int64, length: Int64) -> String? {
        guard offset >= 0, length > 0 else { return nil }
        do {
            try handle.seek(toOffset: UInt64(offset))
            guard let data = try handle.read(upToCount: Int(length)), !data.isEmpty else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
