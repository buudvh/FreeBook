import Foundation

/// Ước tính dung lượng từng nhóm để màn Sao lưu cho người dùng thấy trước khi bật/tắt.
/// Cố ý đo theo thư mục trên đĩa (rẻ, không cần SwiftData) nên chỉ là con số xấp xỉ:
/// archive thật còn được nén, còn `books/*.bin` là append-only nên mang cả phần phình.
public enum BackupSizeEstimator {
    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    public static func estimatedBytes(for scope: BackupScope) -> Int64 {
        switch scope {
        case .books:
            return BackupPaths.fileSize(at: applicationSupport
                .appendingPathComponent("chapters", isDirectory: true)
                .appendingPathComponent("chapter_store.sqlite"))
        case .content:
            return BackupPaths.directorySize(at: applicationSupport.appendingPathComponent("books", isDirectory: true))
        case .extensions:
            return BackupPaths.directorySize(at: ExtensionManager.shared.extensionsDirectory)
        case .dictBooks:
            return BackupPaths.directorySize(at: TranslationManager.shared.translateDirectory
                .appendingPathComponent("books", isDirectory: true))
        case .dictCustom:
            let root = TranslationManager.shared.translateDirectory
            return BackupPaths.globalDictionaryFiles.reduce(0) { total, name in
                total + BackupPaths.fileSize(at: root.appendingPathComponent(name))
            }
        case .dictShared:
            let root = TranslationManager.shared.translateDirectory
            return BackupDictionaryArchiver.sharedFileNames().reduce(0) { total, name in
                total + BackupPaths.fileSize(at: root.appendingPathComponent(name))
            }
        }
    }

    public static func estimatedBytes(for scopes: Set<BackupScope>) -> Int64 {
        scopes.reduce(0) { $0 + estimatedBytes(for: $1) }
    }

    public static func format(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
