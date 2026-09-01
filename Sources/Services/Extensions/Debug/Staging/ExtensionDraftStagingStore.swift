import Foundation

/// Vùng staging cho snapshot nháp gửi từ máy phát triển (Phase 3).
///
/// Nằm ở `applicationSupportDirectory/extension-drafts/`, **ngoài** `extensions/` — nếu để bên trong thì
/// mọi chỗ đang liệt kê thư mục extension sẽ thấy bản nháp như một extension đã cài.
///
/// Ba chốt an toàn, tất cả ở tầng này chứ không ở chỗ gọi:
/// 1. **Không nhận path từ client.** Mọi path đi qua `ExtensionDraftManifest.pathIssue` rồi còn bị kiểm
///    tra containment sau khi resolve (`standardizedFileURL` phải nằm trong thư mục draft).
/// 2. **Không giải nén archive nào.** Server tự `create` từng file từ byte nhận được, nên không có
///    symlink, hard link, hay zip bomb — chỉ có file thường với size đã khai trước.
/// 3. **Chỉ file khai trong manifest** được ghi; chunk cho path lạ bị từ chối.
public actor ExtensionDraftStagingStore {
    public static let shared = ExtensionDraftStagingStore()

    public enum StagingError: LocalizedError {
        case noActiveStage
        case unknownPath(String)
        case unsafePath(String)
        case sizeExceeded(String)
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noActiveStage: return "Chưa có bản nháp nào đang được nạp"
            case .unknownPath(let path): return "Path '\(path)' không có trong manifest"
            case .unsafePath(let path): return "Path '\(path)' không an toàn"
            case .sizeExceeded(let path): return "File '\(path)' vượt size đã khai"
            case .writeFailed(let path): return "Không ghi được '\(path)'"
            }
        }
    }

    private var activeManifest: ExtensionDraftManifest?
    private var receivedBytes: [String: Int] = [:]

    public init() {}

    public static var rootDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("extension-drafts", isDirectory: true)
    }

    public func draftDirectory(packageId: String, revision: String) -> URL? {
        guard ExtensionDraftManifest.pathIssue(packageId) == nil,
              ExtensionDraftManifest.pathIssue(revision) == nil else { return nil }
        return Self.rootDirectory
            .appendingPathComponent(packageId, isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)
    }

    /// Mở một lượt nạp. Manifest sai hình dạng ⇒ trả issue và **không** tạo thư mục nào.
    public func beginStage(_ manifest: ExtensionDraftManifest) -> [String] {
        let issues = manifest.shapeIssues()
        guard issues.isEmpty else { return issues }
        guard let directory = draftDirectory(packageId: manifest.packageId, revision: manifest.revision) else {
            return ["packageId hoặc revision không an toàn"]
        }
        try? FileManager.default.removeItem(at: directory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return ["Không tạo được thư mục staging"]
        }
        activeManifest = manifest
        receivedBytes = [:]
        return []
    }

    public func appendChunk(relativePath: String, data: Data) throws {
        guard let manifest = activeManifest else { throw StagingError.noActiveStage }
        guard let entry = manifest.entries.first(where: { $0.relativePath == relativePath }) else {
            throw StagingError.unknownPath(relativePath)
        }
        guard let directory = draftDirectory(packageId: manifest.packageId, revision: manifest.revision),
              let fileUrl = Self.safeFileURL(relativePath, inside: directory) else {
            throw StagingError.unsafePath(relativePath)
        }
        let already = receivedBytes[relativePath] ?? 0
        guard already + data.count <= entry.size else { throw StagingError.sizeExceeded(relativePath) }

        let parent = fileUrl.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if already == 0 {
            guard (try? data.write(to: fileUrl, options: .atomic)) != nil else {
                throw StagingError.writeFailed(relativePath)
            }
        } else {
            guard let handle = try? FileHandle(forWritingTo: fileUrl) else {
                throw StagingError.writeFailed(relativePath)
            }
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
        receivedBytes[relativePath] = already + data.count
    }

    /// Đóng lượt nạp: xác minh size + SHA-256 của **mọi** entry. Trả issue; rỗng là snapshot toàn vẹn.
    public func finishStage() -> (manifest: ExtensionDraftManifest?, issues: [String]) {
        guard let manifest = activeManifest else { return (nil, ["Chưa có bản nháp nào đang được nạp"]) }
        guard let directory = draftDirectory(packageId: manifest.packageId, revision: manifest.revision) else {
            return (nil, ["Thư mục staging không hợp lệ"])
        }
        var issues: [String] = []
        for entry in manifest.entries {
            guard let fileUrl = Self.safeFileURL(entry.relativePath, inside: directory),
                  let data = try? Data(contentsOf: fileUrl) else {
                issues.append("\(entry.relativePath): thiếu file")
                continue
            }
            if data.count != entry.size {
                issues.append("\(entry.relativePath): nhận \(data.count) byte, khai \(entry.size)")
                continue
            }
            let digest = data.sha256Hex()
            if digest.lowercased() != entry.sha256.lowercased() {
                issues.append("\(entry.relativePath): sha256 không khớp")
            }
        }
        activeManifest = nil
        receivedBytes = [:]
        if !issues.isEmpty {
            try? FileManager.default.removeItem(at: directory)
            return (nil, issues)
        }
        return (manifest, [])
    }

    public func discard(packageId: String, revision: String) {
        guard let directory = draftDirectory(packageId: packageId, revision: revision) else { return }
        try? FileManager.default.removeItem(at: directory)
        if activeManifest?.packageId == packageId, activeManifest?.revision == revision {
            activeManifest = nil
            receivedBytes = [:]
        }
    }

    /// Xoá sạch staging. Gọi lúc khởi động: bản nháp là dữ liệu tạm, không được sống qua lần chạy app.
    public func discardAll() {
        activeManifest = nil
        receivedBytes = [:]
        try? FileManager.default.removeItem(at: Self.rootDirectory)
    }

    public func hasDraft(packageId: String, revision: String) -> Bool {
        guard let directory = draftDirectory(packageId: packageId, revision: revision) else { return false }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent("plugin.json").path)
    }

    /// Resolve path tương đối rồi **kiểm tra lại** containment sau khi standardize — chốt thứ hai sau
    /// `pathIssue`, để một dạng traversal lạ vẫn không ra khỏi thư mục draft.
    private static func safeFileURL(_ relativePath: String, inside directory: URL) -> URL? {
        guard ExtensionDraftManifest.pathIssue(relativePath) == nil else { return nil }
        let candidate = directory.appendingPathComponent(relativePath).standardizedFileURL
        let root = directory.standardizedFileURL.path
        let rootWithSlash = root.hasSuffix("/") ? root : root + "/"
        guard candidate.path.hasPrefix(rootWithSlash) else { return nil }
        return candidate
    }
}
