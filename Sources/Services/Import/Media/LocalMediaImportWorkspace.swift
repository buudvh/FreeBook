import Foundation

/// Thư mục làm việc tạm của một lượt nhập truyện tranh/phim: `tmp/LocalMediaImport/<uuid>/`.
///
/// File người dùng chọn (bản chép `asCopy` của bộ chọn file) được **chuyển** vào đây ngay khi nhận, CBZ giải nén cũng
/// nằm ở đây. Nhập xong (ảnh/phim đã chuyển vào store) hoặc người dùng bỏ ⇒ xoá cả thư mục. Mọi thao tác xoá chỉ chạy
/// với đường dẫn nằm dưới `LocalMediaImport/`.
enum LocalMediaImportWorkspace {
    private static let folderName = "LocalMediaImport"

    /// Thư mục làm việc cũ hơn mốc này là rác của lượt nhập bị app tắt giữa chừng (có thể là phim vài GB).
    private static let staleAge: TimeInterval = 6 * 60 * 60

    static func make() throws -> URL {
        purgeStale()
        let directory = rootURL().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory
    }

    static func discard(_ directory: URL) {
        guard isInside(directory), FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            AppLogger.shared.log("❌ [MediaImport] Không xoá được thư mục tạm: \(error.localizedDescription)")
        }
    }

    /// Đưa file đã chọn vào thư mục làm việc dưới tên `name`: chuyển trước (bản chép của bộ chọn file thuộc về app,
    /// không tốn thêm chỗ), không được mới chép.
    static func adopt(_ picked: URL, into directory: URL, as name: String) throws -> URL {
        let target = directory.appendingPathComponent(name, isDirectory: false)
        guard isInside(target) else {
            throw NSError(domain: "SecurityError", code: 403, userInfo: [NSLocalizedDescriptionKey: "Truy cập file ngoài thư mục tạm bị từ chối."])
        }
        let accessing = picked.startAccessingSecurityScopedResource()
        defer {
            if accessing { picked.stopAccessingSecurityScopedResource() }
        }
        do {
            try FileManager.default.moveItem(at: picked, to: target)
        } catch {
            try FileManager.default.copyItem(at: picked, to: target)
        }
        return target
    }

    static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    /// Dung lượng trống của ổ chứa thư mục tạm (cùng ổ với `applicationSupportDirectory`); `nil` khi hệ điều hành không
    /// trả lời.
    static func availableCapacity() -> Int64? {
        let values = try? FileManager.default.temporaryDirectory
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Dọn thư mục làm việc bỏ dở của các lần chạy trước (app bị tắt giữa lúc chuẩn bị và lúc bấm "Nhập"). Chỉ xoá thư
    /// mục cũ hơn `staleAge` để không đụng lượt nhập đang mở sheet xác nhận.
    private static func purgeStale() {
        let root = rootURL()
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-staleAge)
        for child in children {
            let modified = (try? child.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            if modified < cutoff {
                discard(child)
            }
        }
    }

    private static func rootURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Đường dẫn có nằm dưới `LocalMediaImport/` không.
    ///
    /// iOS trả `temporaryDirectory` dạng `/private/var/…`, và cả `standardizedFileURL` lẫn `resolvingSymlinksInPath`
    /// chỉ bỏ tiền tố `/private` khi đường dẫn **đang tồn tại**. File đích (chưa tạo) mà chuẩn hoá trực tiếp thì giữ
    /// `/private`, còn gốc (đã có) thì không ⇒ lệch tiền tố, mọi file bị từ chối (lỗi 1.3.642). Vì vậy chỉ chuẩn hoá
    /// **thư mục cha** (luôn đã tồn tại lúc gọi) theo cùng cách với gốc rồi ghép tên; tên rỗng / `.` / `..` bị từ chối.
    private static func isInside(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else { return false }
        let root = resolvedPath(rootURL())
        let parent = resolvedPath(url.deletingLastPathComponent())
        return (parent + "/" + name).hasPrefix(root + "/")
    }

    private static func resolvedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
