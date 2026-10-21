import Foundation

/// Thư mục tệp của **một** nguồn (spec §14.2): `applicationSupport/legado_state/files/<packageId>/`. Mọi đường dẫn từ JS
/// là **tương đối** với thư mục này; thoát ra ngoài (`..`, đường dẫn tuyệt đối khác) bị chặn bằng `validatePathSafety`.
///
/// - `downloadFile` giữ tệp qua các lần chạy (nguồn tự quyết khi nào tải lại); thư mục giải nén `*_unzip/` bị dọn ở lần
///   dùng đầu tiên mỗi lần mở app (tài liệu: đệm giải nén xoá ở lần khởi động sau).
/// - Đây là **đệm**, không phải dữ liệu người dùng: Backup không cần gói `legado_state/files/`.
struct LegadoSourceFiles {
    static let maxDownloadBytes = 50 * 1024 * 1024
    private static let cleanupLock = NSLock()
    private static var cleanedPackages: Set<String> = []

    let root: URL

    init(sourceKey: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("legado_state", isDirectory: true)
            .appendingPathComponent("files", isDirectory: true)
            .appendingPathComponent(LegadoSourceIdentity.packageId(forSourceUrl: sourceKey), isDirectory: true)
        cleanStaleUnzipDirectoriesOnce()
    }

    // MARK: - Đường dẫn

    /// URL tuyệt đối của đường dẫn tương đối (`""` ⇒ thư mục gốc của nguồn). Thoát ra ngoài ⇒ ném lỗi.
    func url(for relative: String) throws -> URL {
        var path = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix(root.path) { path = String(path.dropFirst(root.path.count)) }
        while path.hasPrefix("/") { path.removeFirst() }
        let target = path.isEmpty ? root : root.appendingPathComponent(path)
        try validatePathSafety(for: target, allowRoot: path.isEmpty)
        return target
    }

    /// Đường dẫn tương đối (với thư mục của nguồn) của một URL bên trong.
    func relativePath(of url: URL) -> String {
        let rootPath = root.standardized.path
        let full = url.standardized.path
        guard full.hasPrefix(rootPath) else { return url.lastPathComponent }
        var relative = String(full.dropFirst(rootPath.count))
        while relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }

    // MARK: - Đọc / ghi

    func write(_ data: Data, to relative: String) throws -> String {
        let target = try url(for: relative)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        return relativePath(of: target)
    }

    func exists(_ relative: String) -> Bool {
        guard let target = try? url(for: relative) else { return false }
        return FileManager.default.fileExists(atPath: target.path)
    }

    func read(_ relative: String) -> Data? {
        guard let target = try? url(for: relative) else { return nil }
        return try? Data(contentsOf: target)
    }

    /// `java.readTxtFile(path[, charset])`: bảng mã kiểu Java (`ISO8859_1` ⇒ một ký tự mỗi byte, `GBK`…); không có ⇒ `""`.
    func readText(_ relative: String, charset: String?) -> String {
        guard let data = read(relative) else { return "" }
        let encoding = LegadoCharset.encoding(named: charset) ?? .utf8
        return LegadoCharset.string(from: data, encoding: encoding)
    }

    /// `java.deleteFile(path)`.
    func delete(_ relative: String) -> Bool {
        guard let target = try? url(for: relative), target.standardized.path != root.standardized.path,
              FileManager.default.fileExists(atPath: target.path) else { return false }
        return (try? FileManager.default.removeItem(at: target)) != nil
    }

    /// `java.getTxtInFolder(path)` (U58): nối nội dung mọi tệp trong thư mục theo tên tăng dần, cách nhau `\n`.
    func textInFolder(_ relative: String) -> String {
        guard let folder = try? url(for: relative),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return "" }
        return names.sorted().compactMap { name -> String? in
            let file = folder.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue,
                  let data = try? Data(contentsOf: file) else { return nil }
            return LegadoCharset.string(from: data, encoding: .utf8)
        }.joined(separator: "\n")
    }

    /// `java.unzipFile(path)`: giải zip vào `<tên tệp>_unzip/` (xoá bản cũ), trả đường dẫn tương đối của thư mục.
    func unzip(_ relative: String) throws -> String {
        let archive = try url(for: relative)
        guard FileManager.default.fileExists(atPath: archive.path) else {
            throw LegadoJSNativeError("Không có tệp \(relative)")
        }
        let destination = try url(for: relativePath(of: archive) + "_unzip")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        do {
            try BackupZipArchive.extract(archive: archive, to: destination)
        } catch {
            throw LegadoJSNativeError("Giải nén thất bại (chỉ hỗ trợ zip): \(error.localizedDescription)")
        }
        return relativePath(of: destination)
    }

    /// Đọc một mục trong thư mục đã giải nén (chặn thoát thư mục).
    func readEntry(_ entry: String, inFolder folder: String) -> Data? {
        var cleaned = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix("/") { cleaned.removeFirst() }
        return read(folder + "/" + cleaned)
    }

    // MARK: - An toàn đường dẫn

    /// Đường dẫn phải nằm **trong** thư mục của nguồn (sau khi chuẩn hoá và giải symlink).
    private func validatePathSafety(for targetURL: URL, allowRoot: Bool) throws {
        let canonicalRoot = root.standardized.resolvingSymlinksInPath()
        let canonicalTarget = targetURL.standardized.resolvingSymlinksInPath()
        let rootParts = canonicalRoot.pathComponents
        let targetParts = canonicalTarget.pathComponents
        let inside = targetParts.starts(with: rootParts)
            && (targetParts.count > rootParts.count || (allowRoot && targetParts.count == rootParts.count))
        guard inside else {
            throw LegadoJSNativeError("Truy cập tệp ngoài thư mục của nguồn bị từ chối")
        }
    }

    /// Dọn `*_unzip/` của lần chạy app trước (một lần mỗi nguồn mỗi tiến trình).
    private func cleanStaleUnzipDirectoriesOnce() {
        let key = root.lastPathComponent
        Self.cleanupLock.lock()
        let first = Self.cleanedPackages.insert(key).inserted
        Self.cleanupLock.unlock()
        guard first, let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return }
        for name in names where name.hasSuffix("_unzip") {
            let target = root.appendingPathComponent(name)
            guard (try? validatePathSafety(for: target, allowRoot: false)) != nil else { continue }
            try? FileManager.default.removeItem(at: target)
        }
    }
}
