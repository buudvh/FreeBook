import Foundation

/// Gom các file từ điển vào cây staging khi export. Từ điển được sao lưu **nguyên trạng**,
/// không parse — nhờ vậy mục đã xoá (tombstone `key=` giá trị rỗng) đi kèm miễn phí.
public enum BackupDictionaryArchiver {
    public struct Summary: Sendable {
        public var customFiles = 0
        public var bookFolders = 0
        public var sharedFiles = 0
    }

    /// - Parameter slugByBookId: chỉ những bookId có mặt ở đây mới được sao lưu từ điển riêng.
    public static func stage(
        scopes: Set<BackupScope>,
        slugByBookId: [String: String],
        into stagingDirectory: URL
    ) throws -> Summary {
        var summary = Summary()
        let translateRoot = TranslationManager.shared.translateDirectory

        if scopes.contains(.dictCustom) {
            for name in BackupPaths.globalDictionaryFiles {
                let source = translateRoot.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                try BackupZipArchive.stage(
                    fileAt: source,
                    entryName: "\(BackupPaths.globalDictionaryFolder)/\(name)",
                    in: stagingDirectory
                )
                summary.customFiles += 1
            }
            summary.customFiles += try stageTTSDictionaries(into: stagingDirectory)
        }

        if scopes.contains(.dictBooks) {
            let booksRoot = translateRoot.appendingPathComponent("books", isDirectory: true)
            for (bookId, slug) in slugByBookId.sorted(by: { $0.value < $1.value }) {
                var staged = false
                for name in BackupPaths.bookDictionaryFiles {
                    let source = booksRoot.appendingPathComponent(bookId, isDirectory: true).appendingPathComponent(name)
                    guard FileManager.default.fileExists(atPath: source.path) else { continue }
                    try BackupZipArchive.stage(
                        fileAt: source,
                        entryName: "\(BackupPaths.bookDictionaryFolder(slug: slug))/\(name)",
                        in: stagingDirectory
                    )
                    staged = true
                }
                if staged { summary.bookFolders += 1 }
            }
        }

        if scopes.contains(.dictShared) {
            for name in sharedFileNames() {
                let source = translateRoot.appendingPathComponent(name)
                try BackupZipArchive.stage(
                    fileAt: source,
                    entryName: "\(BackupPaths.sharedDictionaryFolder)/\(name)",
                    in: stagingDirectory
                )
                summary.sharedFiles += 1
            }
        }

        return summary
    }

    /// Bộ tiền xử lý TTS ở `FreeBook/TTS/` (từ điển phiên âm cá nhân của NghiTTS, viết tắt, luật
    /// thay ký tự). Cố ý gom vào nhóm `.dictCustom` — xem chú thích ở `BackupPaths`. Trả về số file
    /// đã stage để người gọi cộng vào `Summary.customFiles` (không thêm field mới để giữ nguyên
    /// chữ ký `Summary` cho các call site ngoài file này).
    private static func stageTTSDictionaries(into stagingDirectory: URL) throws -> Int {
        let root = BackupPaths.ttsDictionaryDirectory
        var staged = 0
        for name in BackupPaths.ttsDictionaryFiles {
            let source = root.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try BackupZipArchive.stage(
                fileAt: source,
                entryName: "\(BackupPaths.ttsDictionaryFolder)/\(name)",
                in: stagingDirectory
            )
            staged += 1
        }
        return staged
    }

    /// Danh sách file từ điển chung thực sự có trên máy. Bản `.txt` chỉ được lấy khi **không** có
    /// `.dat` cùng tên, vì hai bản là cùng dữ liệu mà `.txt` rất lớn.
    public static func sharedFileNames() -> [String] {
        let root = TranslationManager.shared.translateDirectory
        var names: [String] = []

        for name in BackupPaths.sharedDictionaryDatFiles
        where FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) {
            names.append(name)
        }

        let stagedDatNames = Set(names)
        for name in BackupPaths.sharedDictionaryTextFiles {
            let datName = (name as NSString).deletingPathExtension + ".dat"
            guard !stagedDatNames.contains(datName) else { continue }
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) else { continue }
            names.append(name)
        }

        for name in BackupPaths.sharedDictionaryAlwaysFiles
        where FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) {
            names.append(name)
        }

        return names
    }
}
