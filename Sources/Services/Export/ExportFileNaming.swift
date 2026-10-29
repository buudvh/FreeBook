import Foundation

/// Đặt tên và cấp phát đường dẫn cho file xuất trong `Documents/Exports/`.
///
/// Trước 1.3.253 bản xuất TXT luôn ghi vào `<tên truyện>.txt` nên lần xuất sau **ghi đè im lặng** lần
/// trước — mất bản đã xuất mà không có cảnh báo nào. Nay tên file mang thêm định dạng và mốc thời
/// gian, và nếu vẫn trùng (hai lần xuất trong cùng một giây) thì thêm hậu tố `-2`, `-3`…
enum ExportFileNaming {
    /// Thư mục xuất duy nhất của app — ngoại lệ có chủ ý so với `applicationSupportDirectory`, vì
    /// người dùng cần thấy file này trong app Files.
    static func exportsDirectory() throws -> URL {
        let fileManager = FileManager.default
        let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exports", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Đường dẫn cuối cùng người dùng nhận được. Không bao giờ trả về đường dẫn đã có file.
    static func targetURL(bookTitle: String, format: BookExportFormat, now: Date = Date()) throws -> URL {
        let directory = try exportsDirectory()
        let base = "\(sanitized(bookTitle))-\(timestamp(now))"
        let fileManager = FileManager.default

        var candidate = directory.appendingPathComponent("\(base).\(format.fileExtension)")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(suffix).\(format.fileExtension)")
            suffix += 1
            if suffix > 100 { break }
        }
        return candidate
    }

    /// Đích tên tự đặt dưới `Exports/` (xuất video: `<Tên phim> - Tập 3.mp4`, hoặc thư mục khi `fileExtension == nil`).
    /// `baseName` phải đã qua `sanitized`. Trùng thì thêm `-2`, `-3`… — không bao giờ trả về đường dẫn đã có file/thư mục.
    static func uniqueURL(baseName: String, fileExtension: String?) throws -> URL {
        let directory = try exportsDirectory()
        let isDirectory = fileExtension == nil
        let tail = fileExtension.map { ".\($0)" } ?? ""
        let fileManager = FileManager.default

        var candidate = directory.appendingPathComponent(baseName + tail, isDirectory: isDirectory)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix)\(tail)", isDirectory: isDirectory)
            suffix += 1
            if suffix > 100 { break }
        }
        try validateInsideExports(candidate)
        return candidate
    }

    /// `<tên>-<yyyyMMdd-HHmmss>` — tên thư mục của bản xuất nhiều file (video nhiều tập).
    static func timestampedName(_ title: String, now: Date = Date()) -> String {
        "\(sanitized(title))-\(timestamp(now))"
    }

    /// Chặn tên lạ (rỗng, `.`, `..`) hay thư mục cha thoát ra ngoài `Documents/Exports/`. Chỉ chuẩn hoá **thư mục cha**
    /// (phải đã tồn tại lúc gọi) rồi ghép tên — chuẩn hoá thẳng đường dẫn chưa tồn tại sẽ lệch tiền tố `/private` với
    /// gốc (bài học `LocalMediaImportWorkspace.isInside`).
    static func validateInsideExports(_ url: URL) throws {
        let name = url.lastPathComponent
        let root = resolvedPath(try exportsDirectory())
        let parent = resolvedPath(url.deletingLastPathComponent())
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              parent == root || parent.hasPrefix(root + "/") else {
            throw NSError(domain: "SecurityError", code: 403, userInfo: [NSLocalizedDescriptionKey: "Truy cập file ngoài thư mục Sandbox bị từ chối."])
        }
    }

    /// File tạm đi kèm: chỉ khi đổi tên thành công thì bản xuất mới tồn tại.
    static func stagingURL(for target: URL) -> URL {
        return target.appendingPathExtension("part")
    }

    /// Bỏ ký tự không hợp lệ trong tên file, giữ đúng cách thay thế cũ để tên bản xuất không đổi kiểu.
    static func sanitized(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Truyen" : String(cleaned.prefix(80))
    }

    private static func resolvedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
