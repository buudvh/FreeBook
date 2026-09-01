import Foundation

/// Lưu và nạp JSON của nguồn Legado trên đĩa.
///
/// Mỗi nguồn là một "extension ảo": thư mục `extensions/<packageId>/` chứa `source.json`. Nhờ vậy
/// `@Model Extension` dùng lại được nguyên vẹn (`localPath` trỏ vào đây) và **không cần đổi schema
/// SwiftData** — schema 5 `@Model` của repo không có `SchemaMigrationPlan`.
public actor LegadoSourceStore {
    public static let shared = LegadoSourceStore()

    private var cache: [String: LegadoBookSource] = [:]

    private init() {}

    private var extensionsRoot: URL? {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let root = paths.first else { return nil }
        return root.appendingPathComponent("extensions", isDirectory: true)
    }

    public func directory(for packageId: String) -> URL? {
        guard let root = extensionsRoot else { return nil }
        let safeName = LegadoPathSafety.sanitizeComponent(packageId)
        let directory = root.appendingPathComponent(safeName, isDirectory: true)
        guard LegadoPathSafety.validate(directory, mustBeUnder: root) else { return nil }
        return directory
    }

    public func sourceFile(for packageId: String) -> URL? {
        directory(for: packageId)?.appendingPathComponent("source.json", isDirectory: false)
    }

    // MARK: - Đọc

    public func source(packageId: String) throws -> LegadoBookSource {
        if let cached = cache[packageId] { return cached }
        guard let url = sourceFile(for: packageId) else {
            throw LegadoRuntimeError.sourceNotFound(packageId)
        }
        guard let data = try? Data(contentsOf: url) else {
            throw LegadoRuntimeError.sourceNotFound(packageId)
        }
        guard let source = LegadoBookSource.parseList(data: data).first else {
            throw LegadoRuntimeError.invalidSourceJSON(url.lastPathComponent)
        }
        cache[packageId] = source
        return source
    }

    /// Đọc nguồn theo `localPath` đã lưu trong `@Model Extension` — dùng khi caller đã có entity.
    public func source(atLocalPath path: String) throws -> LegadoBookSource {
        let url = URL(fileURLWithPath: path).appendingPathComponent("source.json", isDirectory: false)
        guard let data = try? Data(contentsOf: url) else {
            throw LegadoRuntimeError.sourceNotFound(path)
        }
        guard let source = LegadoBookSource.parseList(data: data).first else {
            throw LegadoRuntimeError.invalidSourceJSON(url.lastPathComponent)
        }
        cache[source.packageId] = source
        return source
    }

    // MARK: - Ghi

    /// Ghi nguồn ra đĩa, trả về đường dẫn thư mục để gán vào `Extension.localPath`.
    public func write(_ source: LegadoBookSource) throws -> String {
        guard let directory = directory(for: source.packageId),
              let file = sourceFile(for: source.packageId) else {
            throw LegadoRuntimeError.sourceNotFound(source.packageId)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Ghi lại **JSON gốc** trong một mảng một phần tử: giữ đúng định dạng chia sẻ của Legado và
        // không mất field lạ mà bản này chưa đọc tới.
        let payload: [Any] = [source.rawJSON]
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw LegadoRuntimeError.invalidSourceJSON(source.bookSourceName)
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: file, options: .atomic)
        cache[source.packageId] = source
        return directory.path
    }

    public func remove(packageId: String) {
        cache.removeValue(forKey: packageId)
        guard let directory = directory(for: packageId),
              FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            AppLogger.shared.log("⚠️ [LegadoStore] Xoá nguồn thất bại \(packageId): \(error.localizedDescription)")
        }
    }

    public func invalidateCache(packageId: String? = nil) {
        if let packageId {
            cache.removeValue(forKey: packageId)
        } else {
            cache.removeAll()
        }
    }
}
