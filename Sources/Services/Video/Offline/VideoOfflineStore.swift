import Foundation

/// Bản tải offline của phim: `applicationSupport/videos/<sha256(bookId)>/<episodeIndex>/`.
///
/// Bất biến (theo mẫu `ComicOfflineStore`):
/// - `manifest.json` ghi **sau cùng** ⇒ có manifest ⇔ tập tải trọn vẹn. Thư mục tập không có manifest là bản dở: giữ lại
///   để lần thử sau tải tiếp (khớp `partial.json`), chỉ bị dọn khi người dùng huỷ tác vụ hoặc xoá.
/// - Thư mục tập đặt theo `episodeIndex` của mục lục (`StoredChapterSnapshot.index`), không theo vị trí mảng.
/// - Mọi đường dẫn đi qua `validatePathSafety(for:)` — cài lại độc lập ở đây như các owner file khác.
/// - `videos/` được đánh dấu `isExcludedFromBackup` (không lên iCloud); Backup của app không gói thư mục này.
/// - Không thuộc pipeline text. Xoá sách: `BookStorageManager` / `BookSourceMigrator` gọi `deleteBook`.
enum VideoOfflineStore {
    static let manifestFileName = "manifest.json"
    /// Chữ ký nguồn của bản dở (`VideoHLSDownloader`/`VideoFileDownloader`): khác chữ ký ⇒ dọn thư mục, tải lại từ đầu.
    static let partialFileName = "partial.json"

    struct BookSummary: Equatable, Sendable {
        /// Chỉ số các tập đã tải trọn vẹn (có manifest).
        let completedEpisodes: Set<Int>
        /// Tổng dung lượng: tập trọn vẹn theo manifest, bản dở theo kích thước file thật.
        let totalBytes: Int64
        /// Có thư mục của sách (kể cả chỉ có bản dở) ⇒ còn thứ để xoá.
        let hasFiles: Bool

        static let empty = BookSummary(completedEpisodes: [], totalBytes: 0, hasFiles: false)
    }

    private struct PartialMarker: Codable {
        let signature: String
    }

    // MARK: - Đọc

    static func manifest(bookId: String, episodeIndex: Int) -> VideoEpisodeManifest? {
        let url = episodeDirectoryURL(bookId: bookId, episodeIndex: episodeIndex)
            .appendingPathComponent(manifestFileName, isDirectory: false)
        guard (try? validatePathSafety(for: url)) != nil,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? makeDecoder().decode(VideoEpisodeManifest.self, from: data)
    }

    /// URL file trong thư mục tập. `file` chỉ được là tên file (mọi thành phần thư mục bị bỏ).
    static func fileURL(bookId: String, episodeIndex: Int, file: String) -> URL {
        let safeName = (file as NSString).lastPathComponent
        return episodeDirectoryURL(bookId: bookId, episodeIndex: episodeIndex)
            .appendingPathComponent(safeName, isDirectory: false)
    }

    /// Đường dẫn tương đối dưới `videos/` của một file tập — đoạn sau token trong URL của `VideoOfflineHTTPServer`.
    static func relativePath(bookId: String, episodeIndex: Int, file: String) -> String {
        "\(bookId.sha256())/\(episodeIndex)/\((file as NSString).lastPathComponent)"
    }

    /// Chỉ số các tập đã tải trọn vẹn (có `manifest.json`).
    static func downloadedEpisodeIndexes(bookId: String) -> Set<Int> {
        summary(bookId: bookId).completedEpisodes
    }

    /// Đọc đĩa — gọi ngoài main (`VideoOfflineLibrary.refresh`). Tập trọn vẹn lấy dung lượng từ manifest, bản dở duyệt file.
    static func summary(bookId: String) -> BookSummary {
        let bookDirectory = bookDirectoryURL(bookId: bookId)
        let fileManager = FileManager.default
        guard (try? validatePathSafety(for: bookDirectory)) != nil,
              let entries = try? fileManager.contentsOfDirectory(atPath: bookDirectory.path) else { return .empty }
        var completed = Set<Int>()
        var totalBytes: Int64 = 0
        for entry in entries {
            guard let index = Int(entry) else { continue }
            if let manifest = manifest(bookId: bookId, episodeIndex: index) {
                completed.insert(index)
                totalBytes += manifest.totalBytes
            } else {
                totalBytes += directorySize(bookDirectory.appendingPathComponent(entry, isDirectory: true))
            }
        }
        // Thư mục sách rỗng (xoá dần từng tập / huỷ tập duy nhất) không tính là còn bản tải.
        return BookSummary(completedEpisodes: completed, totalBytes: totalBytes, hasFiles: !completed.isEmpty || totalBytes > 0)
    }

    /// Dung lượng trống còn dùng được cho dữ liệu quan trọng; `nil` khi hệ điều hành không trả lời.
    static func availableCapacity() -> Int64? {
        let values = try? rootDirectoryURL().deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    // MARK: - Ghi (bộ tải)

    /// Tạo thư mục tập nếu chưa có (giữ file của bản dở), bỏ manifest cũ để tập không bị coi là đã tải khi đang tải lại.
    static func prepareEpisodeDirectory(bookId: String, episodeIndex: Int) throws -> URL {
        try ensureRootDirectory()
        let directory = episodeDirectoryURL(bookId: bookId, episodeIndex: episodeIndex)
        try validatePathSafety(for: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let manifestURL = directory.appendingPathComponent(manifestFileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            try FileManager.default.removeItem(at: manifestURL)
        }
        return directory
    }

    /// Bắt đầu (hoặc tiếp) một lượt tải với `signature`. Chữ ký khác bản dở đang có ⇒ xoá sạch file trong thư mục.
    /// Trả `true` khi giữ được file của lượt trước.
    @discardableResult
    static func beginPartial(in directory: URL, signature: String) throws -> Bool {
        try validatePathSafety(for: directory)
        let markerURL = directory.appendingPathComponent(partialFileName, isDirectory: false)
        if let data = try? Data(contentsOf: markerURL),
           let marker = try? JSONDecoder().decode(PartialMarker.self, from: data),
           marker.signature == signature {
            return true
        }
        let fileManager = FileManager.default
        for entry in (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [] {
            try fileManager.removeItem(at: directory.appendingPathComponent(entry))
        }
        try writeAtomic(try JSONEncoder().encode(PartialMarker(signature: signature)), to: markerURL)
        return false
    }

    /// Ghi atomic: file chỉ xuất hiện khi đã đủ byte ⇒ file có mặt = phần đó tải xong.
    static func writeAtomic(_ data: Data, to url: URL) throws {
        try validatePathSafety(for: url)
        try data.write(to: url, options: .atomic)
    }

    /// Ghi manifest — bước cuối, đánh dấu tập đã tải xong; bỏ `partial.json`.
    static func saveManifest(_ manifest: VideoEpisodeManifest, bookId: String, episodeIndex: Int) throws {
        let directory = episodeDirectoryURL(bookId: bookId, episodeIndex: episodeIndex)
        let url = directory.appendingPathComponent(manifestFileName, isDirectory: false)
        try writeAtomic(try makeEncoder().encode(manifest), to: url)
        let markerURL = directory.appendingPathComponent(partialFileName, isDirectory: false)
        try? FileManager.default.removeItem(at: markerURL)
    }

    /// Bỏ bản dở của một tập (người dùng huỷ tác vụ). Tập đã có manifest thì giữ nguyên.
    static func discardPartialEpisode(bookId: String, episodeIndex: Int) {
        guard manifest(bookId: bookId, episodeIndex: episodeIndex) == nil else { return }
        let directory = episodeDirectoryURL(bookId: bookId, episodeIndex: episodeIndex)
        guard FileManager.default.fileExists(atPath: directory.path),
              (try? validatePathSafety(for: directory)) != nil else { return }
        try? FileManager.default.removeItem(at: directory)
        removeBookDirectoryIfEmpty(bookId: bookId)
    }

    // MARK: - Xoá

    static func deleteEpisode(bookId: String, episodeIndex: Int) throws {
        let directory = episodeDirectoryURL(bookId: bookId, episodeIndex: episodeIndex)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try validatePathSafety(for: directory)
        try FileManager.default.removeItem(at: directory)
        removeBookDirectoryIfEmpty(bookId: bookId)
    }

    /// Xoá toàn bộ bản tải của một sách. Không có thư mục thì không làm gì (sách chữ/tranh cũng đi qua đây).
    static func deleteBook(bookId: String) throws {
        let url = bookDirectoryURL(bookId: bookId)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try validatePathSafety(for: url)
        try FileManager.default.removeItem(at: url)
    }

    private static func removeBookDirectoryIfEmpty(bookId: String) {
        let url = bookDirectoryURL(bookId: bookId)
        guard (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.isEmpty == true,
              (try? validatePathSafety(for: url)) != nil else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Đường dẫn

    static func rootDirectoryURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("videos", isDirectory: true)
    }

    /// Thư mục sách — `BookStorageManager` dùng để đẩy vào queue xoá lỗi.
    static func bookDirectoryURL(bookId: String) -> URL {
        rootDirectoryURL().appendingPathComponent(bookId.sha256(), isDirectory: true)
    }

    static func episodeDirectoryURL(bookId: String, episodeIndex: Int) -> URL {
        bookDirectoryURL(bookId: bookId).appendingPathComponent(String(episodeIndex), isDirectory: true)
    }

    /// File dưới `videos/` theo đường dẫn tương đối của URL server; `nil` khi thoát ra ngoài `videos/`.
    static func resolveRelativePath(_ relativePath: String) -> URL? {
        let url = rootDirectoryURL().appendingPathComponent(relativePath, isDirectory: false)
        guard (try? validatePathSafety(for: url)) != nil else { return nil }
        return url
    }

    /// Tạo `videos/` và đánh dấu không sao lưu iCloud (video rất nặng).
    private static func ensureRootDirectory() throws {
        var root = rootDirectoryURL()
        guard !FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try root.setResourceValues(values)
        } catch {
            AppLogger.shared.log("❌ [VideoOffline] Không đánh dấu được videos/ ngoài sao lưu iCloud: \(error.localizedDescription)")
        }
    }

    private static func validatePathSafety(for targetURL: URL) throws {
        let canonicalRoot = rootDirectoryURL().standardized.resolvingSymlinksInPath()
        let canonicalTarget = targetURL.standardized.resolvingSymlinksInPath()
        guard canonicalTarget.pathComponents.starts(with: canonicalRoot.pathComponents) else {
            throw NSError(domain: "SecurityError", code: 403, userInfo: [NSLocalizedDescriptionKey: "Truy cập file ngoài thư mục Sandbox bị từ chối."])
        }
    }

    private static func directorySize(_ directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
