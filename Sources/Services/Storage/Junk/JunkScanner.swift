import CryptoKit
import Foundation

/// Phân loại **rác chắc chắn** cho trang Dọn rác. Hàm thuần, chạy ngoài main, không xoá gì, không đụng SwiftData (danh
/// sách `bookId` và trạng thái bận đến qua `JunkScanInputs`).
///
/// Luật chung: mỗi owner dữ liệu tự biết chính xác file nào nó đang dùng (manifest, dấu tự kiểm, `bookId` còn trong thư
/// viện, cờ đã chuyển xong…); rác là file trong thư mục của **chính owner đó** mà không nằm trong danh sách. Không bao giờ
/// đoán theo tên trên thư mục không rõ chủ. Nhóm VieNeu (Core ML, màn thử, file tải dở) ở `JunkScanner+VieNeu`.
///
/// Mục trùng (nằm trong mục đã lấy ở nhóm trước) chỉ tính một lần; mục thuộc danh sách cấm (`JunkPaths.isProtected`),
/// symlink và mục 0 byte bị bỏ.
enum JunkScanner {
    /// `tmp/`: mục không đổi gì trong chừng này mới coi là của việc đã xong.
    static let staleTemporaryAge: TimeInterval = 60 * 60
    /// Dữ liệu theo truyện: file / thư mục mới đổi trong chừng này chưa coi là mồ côi — truyện có thể đang được lưu (bản
    /// ghi `Book` ghi sau file `.bin`, xem `ChapterPersistenceStore.upsert`). Bằng `CoverCleanupCoordinator.minimumFileAge`.
    static let deletedBookMinimumAge: TimeInterval = 10 * 60

    struct Candidate {
        let url: URL
        let root: URL
    }

    static func scan(_ inputs: JunkScanInputs, now: Date = Date()) -> JunkScanResult {
        var collector = Collector()
        if !inputs.coreMLBusy {
            collector.add(.coreMLStale, coreMLStaleCandidates())
        }
        collector.add(.labData, labDataCandidates())
        if !inputs.anyDownloadBusy {
            collector.add(.partialDownloads, partialDownloadCandidates())
        }
        if !inputs.anyDownloadBusy && !inputs.backupBusy {
            collector.add(.staleTemporary, staleTemporaryCandidates(now: now))
        }
        if let owned = inputs.ownedBookIds, !inputs.bookTaskBusy, !inputs.backupBusy, !inputs.sourceChangeRunning,
           !FileManager.default.fileExists(atPath: JunkPaths.sourceChangeJournal.path) {
            collector.add(.deletedBooks, deletedBookCandidates(owned: owned, now: now))
        }
        collector.add(.legacyExtensionCopy, legacyExtensionCandidates())
        return JunkScanResult(groups: collector.groups, measuredAt: now)
    }

    // MARK: - File tạm

    /// Mỗi mục **ngay trong** `tmp/` mà cả cây của nó không đổi hơn `staleTemporaryAge` (mốc mới nhất của mọi file + thư
    /// mục con: thư mục làm việc như `tmp/LocalMediaImport/<uuid>/` có thể đang dùng dưới một thư mục cha cũ). Bỏ file ẩn.
    static func staleTemporaryCandidates(now: Date) -> [Candidate] {
        let root = JunkPaths.temporaryRoot
        return children(of: root).compactMap { child in
            guard let newest = newestModification(of: child), now.timeIntervalSince(newest) > staleTemporaryAge else {
                return nil
            }
            return Candidate(url: child, root: root)
        }
    }

    // MARK: - Dữ liệu của truyện đã xoá

    /// `books/<hash>.bin`, `comics/<hash>/`, `videos/<hash>/` mà `<hash>` không phải hash của `bookId` nào còn trong thư
    /// viện. Chỉ xét tên đúng 64 ký tự hex thường: `BookBinManager` còn chuyển dần file kiểu cũ `<bookId>.bin` khi mở truyện
    /// — file đó của truyện còn sống, không được coi là rác.
    static func deletedBookCandidates(owned: Set<String>, now: Date) -> [Candidate] {
        let binHashes = Set(owned.map { bookBinHash($0) })
        // `ComicOfflineStore` / `VideoOfflineStore` băm bằng `String.sha256()` (cùng kết quả với `bookBinHash`).
        let mediaHashes = Set(owned.map { $0.sha256() })
        var result: [Candidate] = []

        let booksRoot = JunkPaths.booksRoot
        for child in children(of: booksRoot) {
            let name = child.lastPathComponent
            guard name.hasSuffix(".bin") else { continue }
            let stem = String(name.dropLast(4))
            guard isSHA256Hex(stem), !binHashes.contains(stem), isRegularFile(child),
                  isOlder(child, than: deletedBookMinimumAge, now: now) else { continue }
            result.append(Candidate(url: child, root: booksRoot))
        }

        for root in [JunkPaths.comicsRoot, JunkPaths.videosRoot] {
            for child in children(of: root) {
                let name = child.lastPathComponent
                guard isSHA256Hex(name), !mediaHashes.contains(name), isDirectory(child),
                      isOlder(child, than: deletedBookMinimumAge, now: now) else { continue }
                result.append(Candidate(url: child, root: root))
            }
        }
        return result
    }

    /// Đúng hàm băm của `BookBinManager.sha256Hex` (SHA-256 của UTF-8, hex thường "%02x").
    static func bookBinHash(_ bookId: String) -> String {
        SHA256.hash(data: Data(bookId.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func isSHA256Hex(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    // MARK: - Bản chép thư viện tiện ích cũ

    /// Chỉ đọc cờ `migratedFromLegacy` — **không** qua `ExtensionIndexStore.readInstalled()` (đọc lỗi thì nó cách ly
    /// `installed.json`).
    private struct InstalledIndexFlag: Decodable {
        let migratedFromLegacy: Bool?
    }

    /// Mọi mục trong `extension_store/legacy/` khi `installed.json` ghi đã chuyển xong dữ liệu cũ
    /// (`LegacyExtensionSQLiteMigrator` không bao giờ đọc lại bản chép). Đọc cờ lỗi ⇒ không dọn.
    static func legacyExtensionCandidates() -> [Candidate] {
        guard let data = try? Data(contentsOf: JunkPaths.extensionInstalledIndex),
              let flag = try? JSONDecoder().decode(InstalledIndexFlag.self, from: data),
              flag.migratedFromLegacy == true else { return [] }
        let root = JunkPaths.extensionLegacyDirectory
        return children(of: root).map { Candidate(url: $0, root: root) }
    }

    // MARK: - Tiện ích file

    private static let typeKeys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
    private static let dateKeys: Set<URLResourceKey> = [.contentModificationDateKey, .attributeModificationDateKey]

    /// Mục con trực tiếp của `directory` (bỏ file ẩn); thư mục không có ⇒ rỗng.
    static func children(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(typeKeys.union(dateKeys)),
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: typeKeys))?.isDirectory == true
    }

    static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: typeKeys))?.isRegularFile == true
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: typeKeys))?.isSymbolicLink == true
    }

    static func isOlder(_ url: URL, than age: TimeInterval, now: Date) -> Bool {
        guard let newest = newestModification(of: url) else { return false }
        return now.timeIntervalSince(newest) > age
    }

    /// Mốc đổi mới nhất của `url` và (nếu là thư mục) mọi thứ bên trong — lấy cả mốc đổi thuộc tính (đổi tên / chuyển vào
    /// cũng tính là mới). `nil` khi không đọc được mốc nào của chính `url` ⇒ người gọi coi là mới (không dọn).
    static func newestModification(of url: URL) -> Date? {
        func stamp(_ item: URL) -> Date? {
            guard let values = try? item.resourceValues(forKeys: dateKeys) else { return nil }
            let dates = [values.contentModificationDate, values.attributeModificationDate].compactMap { $0 }
            return dates.max()
        }
        guard var newest = stamp(url) else { return nil }
        guard isDirectory(url), !isSymbolicLink(url),
              let enumerator = FileManager.default.enumerator(
                  at: url,
                  includingPropertiesForKeys: Array(dateKeys),
                  options: [],
                  errorHandler: { _, _ in true }
              ) else { return newest }
        for case let item as URL in enumerator {
            if let date = stamp(item), date > newest { newest = date }
        }
        return newest
    }

    /// Dung lượng thật trên đĩa — cùng cách đo với màn Dung lượng (`StorageUsageScanner`), để "Dọn X" khớp số đo lại sau
    /// khi dọn.
    static func allocatedBytes(of url: URL) -> Int64 {
        isDirectory(url) ? StorageUsageScanner.directorySize(url) : StorageUsageScanner.fileSize(url)
    }

    // MARK: - Gom nhóm

    private struct Collector {
        private(set) var groups: [JunkScanResult.Group] = []
        private var keys: [String] = []

        mutating func add(_ kind: JunkGroupKind, _ candidates: [Candidate]) {
            var items: [JunkScanResult.Item] = []
            for candidate in candidates {
                guard !JunkPaths.isProtected(candidate.url), !JunkScanner.isSymbolicLink(candidate.url) else { continue }
                let key = candidate.url.standardizedFileURL.path
                guard !keys.contains(where: { key == $0 || key.hasPrefix($0 + "/") }) else { continue }
                let bytes = JunkScanner.allocatedBytes(of: candidate.url)
                guard bytes > 0 else { continue }
                keys.append(key)
                items.append(JunkScanResult.Item(url: candidate.url, root: candidate.root, bytes: bytes))
            }
            if !items.isEmpty {
                groups.append(JunkScanResult.Group(kind: kind, items: items))
            }
        }
    }
}
