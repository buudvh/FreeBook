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
    /// Ảnh bìa nằm trong `covers/` như file gốc trên máy (`ImageCacheManager` luôn ghi JPEG).
    public static func cover(slug: String) -> String { "covers/\(slug).jpg" }
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

    /// Bộ tiền xử lý TTS (từ điển phiên âm cá nhân của NghiTTS + viết tắt + luật thay ký tự).
    /// Nằm ở `FreeBook/TTS/` chứ không thuộc `translate/`, nhưng **đi kèm nhóm `.dictCustom`**:
    /// `BackupScope` là `Codable` và rawValue được ghi vào `manifest.scopes`, thêm case mới sẽ
    /// làm bản app cũ decode manifest lỗi.
    public static let ttsDictionaryFolder = "dict/tts"
    public static let ttsDictionaryFiles = [
        "non-vietnamese-words.plist",
        "acronyms.plist",
        "character_replacements.json"
    ]

    /// Cài đặt & cấu hình của app (`UserDefaults`), dạng plist nhị phân. **Không** thuộc nhóm nào:
    /// luôn được ghi vào archive vì chỉ vài KB, còn phía khôi phục bật/tắt bằng
    /// `BackupRestoreWorker.Options.restoreSettings`. Lý do không thêm `BackupScope`: xem
    /// `ttsDictionaryFolder` ở trên.
    public static let settings = "settings/user_defaults.plist"

    /// Cấu hình dạng **file rời** (không nằm trong `UserDefaults`, cũng không phải từ điển): quy tắc
    /// nhận diện mục lục ở `translate/toc_rules.json` và danh sách công cụ tra cứu nhanh. Đi cùng
    /// công tắc `restoreSettings` như khối cài đặt, và cũng **không** thêm `BackupScope` mới.
    public static let tocRules = "config/toc_rules.json"
    public static let searchEngines = "config/search_engines.json"
    public static let tocRulesFileName = "toc_rules.json"

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

    /// Nơi `TextPreprocessor` / `TTSReplacementManager` giữ từ điển phiên âm cá nhân và luật thay
    /// ký tự. Getter chỉ dựng đường dẫn, **không** tạo thư mục — phía phục hồi tự tạo khi cần.
    public static var ttsDictionaryDirectory: URL {
        applicationSupport.appendingPathComponent("FreeBook/TTS", isDirectory: true)
    }

    /// Thư mục tạm dùng làm staging khi nén / giải nén. Người gọi chịu trách nhiệm xoá.
    public static func makeWorkingDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func makeBackupFileName(at date: Date = Date()) -> String {
        return "\(manualBackupPrefix)\(timestamp(at: date)).\(fileExtension)"
    }

    /// Tiền tố phân biệt bản do **lượt tự động** tạo. Việc dọn bản cũ (cả trên máy và trên Drive)
    /// chỉ được chạm vào file có tiền tố này — bản người dùng tự tạo/đổi tên không bao giờ bị xoá hộ.
    public static let autoBackupPrefix = "freebook-auto-"
    private static let manualBackupPrefix = "freebook-"

    public static func makeAutoBackupFileName(at date: Date = Date()) -> String {
        return "\(autoBackupPrefix)\(timestamp(at: date)).\(fileExtension)"
    }

    public static func isAutoBackupFileName(_ name: String) -> Bool {
        name.hasPrefix(autoBackupPrefix) && name.lowercased().hasSuffix(".\(fileExtension)")
    }

    private static func timestamp(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
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
