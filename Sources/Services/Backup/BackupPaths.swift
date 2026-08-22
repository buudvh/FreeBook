import Foundation

/// Nơi duy nhất biết tên entry trong archive và đường dẫn thư mục làm việc của phân hệ backup.
/// Cả `BackupExportWorker` và `BackupRestoreWorker` tra ở đây để hai chiều không lệch tên.
public enum BackupPaths {
    public static let fileExtension = "fbbackup"

    // MARK: - Tên entry trong archive

    public static let manifest = "manifest.json"
    public static let slugs = "library/slugs.json"
    public static let books = "library/books.json"
    public static let repositories = "library/repositories.json"
    public static let extensions = "library/extensions.json"

    public static func chapters(slug: String) -> String { "chapters/\(slug).json" }
    public static func content(slug: String) -> String { "content/\(slug).bin" }
    public static func extensionFolder(packageId: String) -> String { "extensions/\(packageId)" }

    /// `extensions/common` — thư viện JS dùng chung mà extension `load()` tới. Không phải một
    /// package nên được xử lý riêng ở cả hai chiều.
    public static let extensionCommonFolder = "extensions/common"
    public static let extensionCommonFolderName = "common"

    public static let globalDictionaryFolder = "dict/global"
    public static let sharedDictionaryFolder = "dict/shared"
    public static func bookDictionaryFolder(slug: String) -> String { "dict/books/\(slug)" }

    /// Custom VietPhrase/Names dùng chung — tombstone (value rỗng) nằm ngay trong hai file này.
    public static let globalDictionaryFiles = ["CustomVietPhrase.txt", "CustomNames.txt"]

    /// Từ điển riêng của một truyện, nằm ở `translate/books/<bookId>/`.
    public static let bookDictionaryFiles = ["VietPhrase.txt", "Names.txt"]

    /// Từ điển chung dạng nhị phân. Chỉ lấy `<Name>.txt` khi **không** có `.dat` cùng tên
    /// để tránh nhân đôi vài chục MB.
    public static let sharedDictionaryDatFiles = ["VietPhrase.dat", "Names.dat", "Pronouns.dat", "LuatNhan.dat"]
    public static let sharedDictionaryTextFiles = ["VietPhrase.txt", "Names.txt", "Pronouns.txt", "LuatNhan.txt"]
    /// Không có bản `.dat`, luôn lấy nguyên file text.
    public static let sharedDictionaryAlwaysFiles = ["ChinesePhienAmWords.txt"]

    // MARK: - Thư mục trên máy

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Nơi giữ các file `.fbbackup` tạo trong app.
    public static var backupsDirectory: URL {
        let directory = applicationSupport.appendingPathComponent("backups", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Thư mục tạm dùng làm staging khi nén / giải nén. Người gọi chịu trách nhiệm xoá.
    public static func makeWorkingDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func makeBackupFileName(at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "freebook-\(formatter.string(from: date)).\(fileExtension)"
    }

    /// Dung lượng thật của một file (0 nếu không đọc được).
    public static func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    /// Tổng dung lượng một cây thư mục, dùng cho phần ước tính dung lượng nhóm trong UI.
    public static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}
