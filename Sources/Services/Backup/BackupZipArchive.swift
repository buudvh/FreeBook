import Foundation
import ZIPFoundation

/// **File duy nhất trong repo được phép gọi ZIPFoundation** ngoài `ExtensionManager`.
///
/// Chỉ dùng hai API mở rộng của `FileManager` (`zipItem` / `unzipItem`) vì chúng giữ nguyên chữ ký
/// suốt dòng 0.9.x, còn `Archive.init` đổi giữa dạng optional (≤ 0.9.18) và dạng `throws` (0.9.19+)
/// mà repo không commit `Package.resolved` nên không biết trước bản nào được resolve.
///
/// Hệ quả của lựa chọn này: export phải dựng sẵn cây file staging trên đĩa rồi nén cả thư mục.
/// Để không nhân đôi dung lượng cho các file lớn (`.bin`, `.dat`), `stage` thử hard link trước.
public enum BackupZipArchive {
    /// Nén toàn bộ **nội dung** của `stagingDirectory` (không giữ thư mục cha) vào `destination`.
    public static func makeArchive(from stagingDirectory: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.zipItem(
            at: stagingDirectory,
            to: destination,
            shouldKeepParent: false,
            compressionMethod: .deflate
        )
    }

    /// Giải nén `archive` vào `destination` (thư mục sẽ được tạo nếu chưa có).
    public static func extract(archive: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: archive, to: destination)
    }

    // MARK: - Dựng cây staging

    /// Đưa `data` vào staging dưới tên entry `entryName`.
    public static func stage(data: Data, entryName: String, in stagingDirectory: URL) throws {
        let target = try prepare(entryName: entryName, in: stagingDirectory)
        try data.write(to: target, options: .atomic)
    }

    /// Đưa một file có sẵn vào staging. Thử hard link trước (không tốn thêm dung lượng),
    /// thất bại thì copy.
    public static func stage(fileAt source: URL, entryName: String, in stagingDirectory: URL) throws {
        let target = try prepare(entryName: entryName, in: stagingDirectory)
        do {
            try FileManager.default.linkItem(at: source, to: target)
        } catch {
            try FileManager.default.copyItem(at: source, to: target)
        }
    }

    /// Đưa cả một thư mục (đệ quy) vào staging dưới tên entry `entryName`.
    public static func stage(directoryAt source: URL, entryName: String, in stagingDirectory: URL) throws {
        let target = stagingDirectory.appendingPathComponent(entryName, isDirectory: true)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: source, to: target)
    }

    /// Đọc một entry đã giải nén; `nil` nếu entry không có trong archive.
    public static func readStaged(entryName: String, in extractedDirectory: URL) -> Data? {
        let url = extractedDirectory.appendingPathComponent(entryName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// URL của một entry đã giải nén; `nil` nếu không tồn tại.
    public static func stagedURL(entryName: String, in extractedDirectory: URL) -> URL? {
        let url = extractedDirectory.appendingPathComponent(entryName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private static func prepare(entryName: String, in stagingDirectory: URL) throws -> URL {
        let target = stagingDirectory.appendingPathComponent(entryName)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        return target
    }
}
