import Foundation
import ImageIO

/// Ảnh comic tải offline: `applicationSupport/comics/<sha256(bookId)>/<chapterIndex>/` gồm các ảnh
/// `0001.<ext>` (đuôi theo magic bytes) và `manifest.json` (`ComicChapterManifest`).
///
/// Bất biến:
/// - `manifest.json` ghi **sau cùng** ⇒ có manifest ⇔ chương tải trọn vẹn. Chương dở dang (lỗi/huỷ) bị xoá cả thư mục.
/// - Thư mục chương đặt theo `chapterIndex` của mục lục (`StoredChapterSnapshot.index`), không theo vị trí mảng.
/// - Mọi đường dẫn đi qua `validatePathSafety(for:)` — cài lại độc lập theo mẫu `BookBinManager`/`ImageCacheManager`.
/// - Không thuộc pipeline text: không đụng `BookBinManager`/`ChapterStore`. Xoá sách: `BookStorageManager` gọi `deleteBook`.
public enum ComicOfflineStore {
    static let manifestFileName = "manifest.json"

    // MARK: - Đọc

    public static func manifest(bookId: String, chapterIndex: Int) -> ComicChapterManifest? {
        let url = chapterDirectoryURL(bookId: bookId, chapterIndex: chapterIndex)
            .appendingPathComponent(manifestFileName, isDirectory: false)
        guard (try? validatePathSafety(for: url)) != nil,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? makeDecoder().decode(ComicChapterManifest.self, from: data)
    }

    /// URL ảnh của một trang trong manifest. `file` chỉ được là tên file (mọi thành phần thư mục bị bỏ).
    public static func pageFileURL(bookId: String, chapterIndex: Int, file: String) -> URL {
        let safeName = (file as NSString).lastPathComponent
        return chapterDirectoryURL(bookId: bookId, chapterIndex: chapterIndex)
            .appendingPathComponent(safeName, isDirectory: false)
    }

    /// Chỉ số các chương đã tải trọn vẹn (có `manifest.json`).
    public static func downloadedChapterIndexes(bookId: String) -> Set<Int> {
        let bookDirectory = bookDirectoryURL(bookId: bookId)
        guard (try? validatePathSafety(for: bookDirectory)) != nil,
              let entries = try? FileManager.default.contentsOfDirectory(atPath: bookDirectory.path) else { return [] }
        var indexes = Set<Int>()
        for entry in entries {
            guard let index = Int(entry) else { continue }
            let manifestPath = bookDirectory
                .appendingPathComponent(entry, isDirectory: true)
                .appendingPathComponent(manifestFileName, isDirectory: false)
                .path
            if FileManager.default.fileExists(atPath: manifestPath) {
                indexes.insert(index)
            }
        }
        return indexes
    }

    // MARK: - Xoá

    /// Xoá toàn bộ ảnh offline của một sách. Không có thư mục thì không làm gì (sách chữ cũng đi qua đây).
    public static func deleteBook(bookId: String) throws {
        let url = bookDirectoryURL(bookId: bookId)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try validatePathSafety(for: url)
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Ghi (chỉ `DownloadManager+Comic`)

    /// Thư mục sách — `BookStorageManager` dùng để đẩy vào queue xoá lỗi.
    static func bookDirectoryURL(bookId: String) -> URL {
        rootDirectoryURL().appendingPathComponent(bookId.sha256(), isDirectory: true)
    }

    /// Dọn thư mục chương còn sót (lượt tải trước bị ngắt) rồi tạo mới, trả về URL thư mục.
    static func prepareChapterDirectory(bookId: String, chapterIndex: Int) throws -> URL {
        let directory = chapterDirectoryURL(bookId: bookId, chapterIndex: chapterIndex)
        try validatePathSafety(for: directory)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory
    }

    /// Ghi ảnh thứ `pageNumber` (bắt đầu từ 1) vào thư mục chương; trả về mục manifest của nó.
    static func writePage(
        _ data: Data,
        pageNumber: Int,
        chapterDirectory: URL,
        knownWidth: Int?,
        knownHeight: Int?
    ) throws -> ComicChapterManifest.Page {
        let fileName = String(format: "%04d", pageNumber) + "." + fileExtension(for: data)
        let url = chapterDirectory.appendingPathComponent(fileName, isDirectory: false)
        try validatePathSafety(for: url)
        try data.write(to: url, options: .atomic)

        let measured = (knownWidth != nil && knownHeight != nil) ? nil : pixelSize(of: data)
        return ComicChapterManifest.Page(
            file: fileName,
            width: knownWidth ?? measured?.width,
            height: knownHeight ?? measured?.height
        )
    }

    /// Ghi manifest — bước cuối, đánh dấu chương đã tải xong.
    static func saveManifest(_ manifest: ComicChapterManifest, bookId: String, chapterIndex: Int) throws {
        let url = chapterDirectoryURL(bookId: bookId, chapterIndex: chapterIndex)
            .appendingPathComponent(manifestFileName, isDirectory: false)
        try validatePathSafety(for: url)
        let data = try makeEncoder().encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    /// Bỏ chương dở dang (lỗi hoặc huỷ giữa chừng).
    static func discardChapter(bookId: String, chapterIndex: Int) {
        let directory = chapterDirectoryURL(bookId: bookId, chapterIndex: chapterIndex)
        guard FileManager.default.fileExists(atPath: directory.path),
              (try? validatePathSafety(for: directory)) != nil else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Đường dẫn

    private static func rootDirectoryURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("comics", isDirectory: true)
    }

    private static func chapterDirectoryURL(bookId: String, chapterIndex: Int) -> URL {
        bookDirectoryURL(bookId: bookId).appendingPathComponent(String(chapterIndex), isDirectory: true)
    }

    private static func validatePathSafety(for targetURL: URL) throws {
        let canonicalRoot = rootDirectoryURL().standardized.resolvingSymlinksInPath()
        let canonicalTarget = targetURL.standardized.resolvingSymlinksInPath()
        guard canonicalTarget.pathComponents.starts(with: canonicalRoot.pathComponents) else {
            throw NSError(domain: "SecurityError", code: 403, userInfo: [NSLocalizedDescriptionKey: "Truy cập file ngoài thư mục Sandbox bị từ chối."])
        }
    }

    // MARK: - Định dạng

    /// Đuôi file theo magic bytes. Chỉ để dễ nhận diện khi xem thư mục — ImageIO đọc theo nội dung, không theo đuôi.
    static func fileExtension(for data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        func matches(_ signature: [UInt8], at offset: Int = 0) -> Bool {
            guard bytes.count >= offset + signature.count else { return false }
            return Array(bytes[offset..<(offset + signature.count)]) == signature
        }
        if matches([0xFF, 0xD8, 0xFF]) { return "jpg" }
        if matches([0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if matches([0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if matches([0x52, 0x49, 0x46, 0x46]) && matches([0x57, 0x45, 0x42, 0x50], at: 8) { return "webp" }
        if matches([0x42, 0x4D]) { return "bmp" }
        if matches([0x66, 0x74, 0x79, 0x70], at: 4) {
            // ISO-BMFF: brand ở byte 8..11 (`avif`/`avis` hoặc `heic`/`heix`/`mif1`…).
            let brand = String(decoding: bytes.count >= 12 ? Array(bytes[8..<12]) : [], as: UTF8.self)
            return brand.hasPrefix("avi") ? "avif" : "heic"
        }
        return "img"
    }

    /// Kích thước điểm ảnh đọc từ header (không giải mã), đã tính EXIF xoay 90°.
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return orientation >= 5 ? (width: height, height: width) : (width: width, height: height)
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
