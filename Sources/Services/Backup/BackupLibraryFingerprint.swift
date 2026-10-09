import CryptoKit
import Foundation
import SwiftData

/// Dấu vân tay SHA-256 của **đúng những gì lượt sao lưu tự động sẽ đưa vào archive** — để lượt theo
/// lịch bỏ qua khi kể từ lượt thành công trọn vẹn gần nhất không có gì đổi.
///
/// Mỗi mục dưới đây khớp một bước của `BackupExportWorker.export`; thêm/bớt thứ gì trong archive thì
/// phải sửa ở đây cùng lúc, nếu không cổng sẽ bỏ qua một thay đổi có thật:
/// - `library/*.json` + `slugs.json`: băm lại chính DTO của `BackupLibraryReader` (cùng reader với
///   export), mã hoá JSON khoá sắp xếp, cùng chiến lược ngày `.iso8601` ⇒ khác byte nào trong
///   archive thì khác dấu vân tay. Slug là hàm thuần của thứ tự `books` + `orphanDictionaryBookIds`.
/// - `chapters/<slug>.json`: từng dòng mục lục qua `ChapterStore.fetchOrderedTOC` (đúng API export
///   dùng) — chỉ metadata, **không** đọc nội dung chương.
/// - `content/<slug>.bin`, `covers/<slug>.jpg`, thư mục extension, từ điển, file cấu hình rời: tên +
///   kích thước + mốc sửa đổi (file `.bin` chỉ ghi nối thêm nên mọi lần ghi đều đổi kích thước).
/// - `settings/user_defaults.plist`: chính ảnh chụp `BackupSettingsArchiver.exportableSnapshot()`,
///   băm theo khoá đã sắp xếp (plist của dictionary không ổn định thứ tự giữa các lần chạy).
/// - `manifest.json`: schema + phiên bản app + nhóm nội dung; `createdAt` cố ý bỏ (luôn khác).
/// - Ngoài archive: tập đích đang bật — bật thêm Telegram thì phải gửi lại dù thư viện không đổi —
///   cộng digest của refresh token Drive: liên kết lại (tài khoản khác) cũng là một đích mới.
///
/// Sai lệch an toàn duy nhất được chấp nhận là **chạy thừa** (mốc sửa đổi đổi mà nội dung không đổi);
/// hướng ngược lại — bỏ qua khi archive lẽ ra đã khác — là bug.
///
/// Không gắn actor: hàm `async` không cô lập nên chạy ngoài main thread kể cả khi coordinator
/// (`@MainActor`) gọi. `ModelContext` riêng chỉ sống trong một câu lệnh, không vắt qua `await`.
enum BackupLibraryFingerprint {
    /// Tăng khi đổi cách băm: dấu vân tay đã lưu tự lệch, lượt kế tiếp chạy đủ.
    private static let formatVersion: Int64 = 2

    /// Digest kèm số lượng lần đọc này thấy — để đối chiếu với `manifest.counts` của archive: export tự
    /// nuốt lỗi đọc (`try?`), nên archive thiếu mà vẫn "thành công" thì không được lưu dấu vân tay.
    struct Value: Equatable, Sendable {
        let digest: String
        let books: Int
        let collections: Int
        let repositories: Int
        let extensions: Int
        let tocRows: Int

        /// Archive có chứa đúng những gì lần đọc này thấy không (theo số lượng).
        func matches(_ counts: BackupManifest.Counts) -> Bool {
            counts.books == books && counts.collections == collections
                && counts.repositories == repositories && counts.extensions == extensions
                && counts.chapters == tocRows
        }
    }

    /// `nil` khi không đọc được mục lục của một truyện — khi đó cổng không áp dụng (chạy như cũ) và
    /// lượt này không được lưu dấu vân tay.
    static func compute(
        container: ModelContainer,
        scopes requestedScopes: Set<BackupScope>,
        driveEnabled: Bool,
        telegramEnabled: Bool
    ) async -> Value? {
        // Giống `BackupExportWorker.init`: nhóm `.books` luôn có.
        let scopes = requestedScopes.union([.books])
        let payload = BackupLibraryReader(container: container).read(scopes: scopes)

        var hasher = SHA256()
        feed(formatVersion, into: &hasher)
        feedRunShape(scopes: scopes, driveEnabled: driveEnabled, telegramEnabled: telegramEnabled, into: &hasher)
        guard feedLibrary(payload, scopes: scopes, into: &hasher) else { return nil }

        var tocRows = 0
        for book in payload.books {
            let toc: [StoredChapterSnapshot]
            do {
                toc = try await ChapterStore.shared.fetchOrderedTOC(bookId: book.bookId)
            } catch {
                AppLogger.shared.log("⚠️ [Backup] Không đọc được mục lục \(book.bookId) để so thay đổi: \(error.localizedDescription)")
                return nil
            }
            tocRows += toc.count
            feedTOC(bookId: book.bookId, toc: toc, into: &hasher)
        }

        // Cùng luật với export: tắt nhóm `.content` thì vẫn gom `.bin` của truyện local/TXT.
        let contentBooks = scopes.contains(.content) ? payload.books : payload.books.filter { $0.isLocalBook }
        var binFiles: [(bookId: String, url: URL)] = []
        for book in contentBooks {
            let url = await BookBinManager.shared.binFilePath(for: book.bookId)
            binFiles.append((book.bookId, url))
        }
        feed("content", into: &hasher)
        for entry in binFiles {
            feedFile(label: entry.bookId, at: entry.url, into: &hasher)
        }

        feedCovers(books: payload.books, into: &hasher)
        if scopes.contains(.extensions) {
            feedExtensionFolders(records: payload.extensions, into: &hasher)
        }
        let dictionaryBookIds = Set(payload.books.map { $0.bookId } + payload.orphanDictionaryBookIds).sorted()
        feedDictionaries(scopes: scopes, bookIds: dictionaryBookIds, into: &hasher)
        feedSettings(into: &hasher)
        feedConfigFiles(into: &hasher)

        return Value(
            digest: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
            books: payload.books.count,
            collections: payload.collections.count,
            repositories: payload.repositories.count,
            extensions: payload.extensions.count,
            tocRows: tocRows
        )
    }

    // MARK: - Từng phần của archive

    /// `manifest.json` (trừ `createdAt` và `counts` — counts suy ra từ chính các phần bên dưới) cộng
    /// tập đích đang bật.
    private static func feedRunShape(
        scopes: Set<BackupScope>,
        driveEnabled: Bool,
        telegramEnabled: Bool,
        into hasher: inout SHA256
    ) {
        feed("manifest", into: &hasher)
        feed(Int64(BackupManifest.currentSchemaVersion), into: &hasher)
        feed(BackupManifest.runningAppVersion, into: &hasher)
        let orderedScopes = BackupScope.displayOrder.filter { scopes.contains($0) }
        feed(Int64(orderedScopes.count), into: &hasher)
        for scope in orderedScopes {
            feed(scope.rawValue, into: &hasher)
        }
        feed("destinations", into: &hasher)
        feed(driveEnabled ? 1 : 0, into: &hasher)
        if driveEnabled {
            // Danh tính tài khoản Drive đang liên kết: chỉ băm digest của refresh token (token chỉ được
            // lưu lúc đăng nhập nên ổn định giữa các lượt), không log, không lưu token thô.
            let token = GoogleDriveTokenStore.loadRefreshToken() ?? ""
            feedData(Data(SHA256.hash(data: Data(token.utf8))), into: &hasher)
        }
        feed(telegramEnabled ? 1 : 0, into: &hasher)
    }

    /// `library/books.json`, `collections.json`, và khi có nhóm `.extensions` thì `repositories.json` +
    /// `extensions.json`; cộng danh sách bookId chỉ còn từ điển (nguồn của `slugs.json`).
    private static func feedLibrary(
        _ payload: BackupLibraryReader.Payload,
        scopes: Set<BackupScope>,
        into hasher: inout SHA256
    ) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            feed("books", into: &hasher)
            feedData(try encoder.encode(payload.books), into: &hasher)
            feed("collections", into: &hasher)
            feedData(try encoder.encode(payload.collections), into: &hasher)
            if scopes.contains(.extensions) {
                feed("repositories", into: &hasher)
                feedData(try encoder.encode(payload.repositories), into: &hasher)
                feed("extensions", into: &hasher)
                feedData(try encoder.encode(payload.extensions), into: &hasher)
            }
        } catch {
            AppLogger.shared.log("⚠️ [Backup] Không mã hoá được thư viện để so thay đổi: \(error.localizedDescription)")
            return false
        }
        feed("orphanDictionaryBookIds", into: &hasher)
        feed(Int64(payload.orphanDictionaryBookIds.count), into: &hasher)
        for bookId in payload.orphanDictionaryBookIds {
            feed(bookId, into: &hasher)
        }
        return true
    }

    /// Đủ mọi trường của `BackupPayload.ChapterRecord`. `updatedAt` băm nguyên độ chính xác (chặt hơn
    /// `.iso8601` của archive) — chỉ có thể sinh chạy thừa, không bỏ sót.
    private static func feedTOC(bookId: String, toc: [StoredChapterSnapshot], into hasher: inout SHA256) {
        feed("toc", into: &hasher)
        feed(bookId, into: &hasher)
        feed(Int64(toc.count), into: &hasher)
        for row in toc {
            feed(Int64(row.index), into: &hasher)
            feed(row.title, into: &hasher)
            feed(row.url, into: &hasher)
            feedOptional(row.host, into: &hasher)
            feedOptional(row.titleTrans, into: &hasher)
            feed(row.isCached ? 1 : 0, into: &hasher)
            feed(row.offset, into: &hasher)
            feed(row.length, into: &hasher)
            feed(row.updatedAt, into: &hasher)
        }
    }

    /// Đúng điều kiện của `BackupCoverArchiver.stage`: chỉ bìa không tải lại được.
    private static func feedCovers(books: [BackupPayload.BookRecord], into hasher: inout SHA256) {
        feed("covers", into: &hasher)
        for book in books where book.hasUnrecoverableCover {
            feedFile(label: book.bookId, at: ImageCacheManager.shared.localCoverURL(for: book.bookId), into: &hasher)
        }
    }

    /// Thư mục `extensions/<packageId>/` của từng extension trong `extensions.json`, cộng `extensions/common`.
    private static func feedExtensionFolders(records: [BackupPayload.ExtensionRecord], into hasher: inout SHA256) {
        let root = ExtensionManager.shared.extensionsDirectory
        feed("extensionFolders", into: &hasher)
        for record in records {
            feedDirectoryTree(label: record.packageId, at: root.appendingPathComponent(record.packageId, isDirectory: true), into: &hasher)
        }
        feedDirectoryTree(
            label: BackupPaths.extensionCommonFolderName,
            at: root.appendingPathComponent(BackupPaths.extensionCommonFolderName, isDirectory: true),
            into: &hasher
        )
    }

    /// Cùng danh sách file `BackupDictionaryArchiver.stage` gom theo từng nhóm.
    private static func feedDictionaries(scopes: Set<BackupScope>, bookIds: [String], into hasher: inout SHA256) {
        let translateRoot = TranslationManager.shared.translateDirectory
        feed("dictionaries", into: &hasher)
        if scopes.contains(.dictCustom) {
            for name in BackupPaths.globalDictionaryFiles {
                feedFile(label: "global/\(name)", at: translateRoot.appendingPathComponent(name), into: &hasher)
            }
            for name in BackupPaths.ttsDictionaryFiles {
                feedFile(label: "tts/\(name)", at: BackupPaths.ttsDictionaryDirectory.appendingPathComponent(name), into: &hasher)
            }
        }
        if scopes.contains(.dictBooks) {
            let booksRoot = translateRoot.appendingPathComponent("books", isDirectory: true)
            let names = BackupPaths.bookDictionaryFiles + BackupPaths.bookTTSFiles + BackupPaths.bookRuleFiles
            for bookId in bookIds {
                let folder = booksRoot.appendingPathComponent(bookId, isDirectory: true)
                for name in names {
                    feedFile(label: "books/\(bookId)/\(name)", at: folder.appendingPathComponent(name), into: &hasher)
                }
            }
        }
        if scopes.contains(.dictShared) {
            for name in BackupDictionaryArchiver.sharedFileNames() {
                feedFile(label: "shared/\(name)", at: translateRoot.appendingPathComponent(name), into: &hasher)
            }
        }
    }

    /// Khối `settings/user_defaults.plist`: cùng bộ lọc khoá với archiver.
    private static func feedSettings(into hasher: inout SHA256) {
        let snapshot = BackupSettingsArchiver.exportableSnapshot()
        feed("settings", into: &hasher)
        feedPropertyList(snapshot, into: &hasher)
    }

    /// Các entry `config/*` của `BackupConfigArchiver.stage`.
    private static func feedConfigFiles(into hasher: inout SHA256) {
        feed("config", into: &hasher)
        feedFile(
            label: BackupPaths.tocRulesFileName,
            at: TranslationManager.shared.translateDirectory.appendingPathComponent(BackupPaths.tocRulesFileName),
            into: &hasher
        )
        // Archive chép nguyên byte của khoá này nên băm đúng byte đó.
        feed("searchEngines", into: &hasher)
        if let data = UserDefaults.standard.data(forKey: SearchEngine.storageKey) {
            feed(1, into: &hasher)
            feedData(data, into: &hasher)
        } else {
            feed(0, into: &hasher)
        }
        feedFile(label: "quickTranslateRules", at: QuickTranslationRuleStore.shared.ruleFileURL, into: &hasher)
        feedFile(
            label: "quickTranslateRulesDisabled",
            at: QuickTranslationRuleDisableStore.shared.fileURL(for: .global),
            into: &hasher
        )
        let memoryFiles = (try? FileManager.default.contentsOfDirectory(
            at: BackupPaths.aiMemoryDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        let memoryTexts = memoryFiles
            .filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        feed("aiMemory", into: &hasher)
        feed(Int64(memoryTexts.count), into: &hasher)
        for file in memoryTexts {
            feedFile(label: file.lastPathComponent, at: file, into: &hasher)
        }
    }

    // MARK: - File trên đĩa

    /// Tên + kích thước + mốc sửa đổi; file không có (hoặc không phải file thường) cũng là một trạng thái.
    private static func feedFile(label: String, at url: URL, into hasher: inout SHA256) {
        feed(label, into: &hasher)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else {
            feed(0, into: &hasher)
            return
        }
        feed(1, into: &hasher)
        feed(Int64(values.fileSize ?? 0), into: &hasher)
        feed(values.contentModificationDate ?? Date.distantPast, into: &hasher)
    }

    /// Mọi file thường trong cây (kể cả file ẩn — `copyItem` của archive chép cả chúng), theo đường dẫn
    /// tương đối đã sắp xếp. Đường dẫn tuyệt đối chứa UUID container nên không được băm.
    private static func feedDirectoryTree(label: String, at root: URL, into hasher: inout SHA256) {
        feed(label, into: &hasher)
        guard (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            feed(-1, into: &hasher)
            return
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let rootPath = root.standardizedFileURL.path
        var entries: [(path: String, size: Int64, modified: Date)] = []
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) {
            for case let item as URL in enumerator {
                guard let values = try? item.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                    continue
                }
                let path = item.standardizedFileURL.path
                let relative = path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : item.lastPathComponent
                entries.append((relative, Int64(values.fileSize ?? 0), values.contentModificationDate ?? Date.distantPast))
            }
        }
        entries.sort { $0.path < $1.path }
        feed(Int64(entries.count), into: &hasher)
        for entry in entries {
            feed(entry.path, into: &hasher)
            feed(entry.size, into: &hasher)
            feed(entry.modified, into: &hasher)
        }
    }

    // MARK: - Mã hoá chính tắc

    /// Dictionary đi theo khoá đã sắp xếp, mảng theo thứ tự; giá trị lá mã hoá bằng plist nhị phân của
    /// mảng một phần tử (giữ phân biệt `Bool`/`Int`/`Double`/`Date`/`Data` như chính archive).
    private static func feedPropertyList(_ value: Any, into hasher: inout SHA256) {
        if let dictionary = value as? [String: Any] {
            feed("{", into: &hasher)
            feed(Int64(dictionary.count), into: &hasher)
            for (key, element) in dictionary.sorted(by: { $0.key < $1.key }) {
                feed(key, into: &hasher)
                feedPropertyList(element, into: &hasher)
            }
        } else if let array = value as? [Any] {
            feed("[", into: &hasher)
            feed(Int64(array.count), into: &hasher)
            for element in array {
                feedPropertyList(element, into: &hasher)
            }
        } else if let data = try? PropertyListSerialization.data(fromPropertyList: [value], format: .binary, options: 0) {
            feedData(data, into: &hasher)
        } else {
            feed("?", into: &hasher)
        }
    }

    private static func feedOptional(_ text: String?, into hasher: inout SHA256) {
        guard let text else {
            feed(0, into: &hasher)
            return
        }
        feed(1, into: &hasher)
        feed(text, into: &hasher)
    }

    /// Mọi chuỗi/khối byte đều có tiền tố độ dài — hai trường liền nhau không thể ghép thành cùng một dòng byte.
    private static func feed(_ text: String, into hasher: inout SHA256) {
        feedData(Data(text.utf8), into: &hasher)
    }

    private static func feedData(_ data: Data, into hasher: inout SHA256) {
        feed(Int64(data.count), into: &hasher)
        hasher.update(data: data)
    }

    private static func feed(_ date: Date, into hasher: inout SHA256) {
        feed(Int64(bitPattern: date.timeIntervalSinceReferenceDate.bitPattern), into: &hasher)
    }

    private static func feed(_ number: Int64, into hasher: inout SHA256) {
        var littleEndian = number.littleEndian
        withUnsafeBytes(of: &littleEndian) { hasher.update(bufferPointer: $0) }
    }
}
