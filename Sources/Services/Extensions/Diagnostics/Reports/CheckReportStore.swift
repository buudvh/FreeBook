import Foundation

/// Chủ **duy nhất** của hai thư mục báo cáo kiểm tra (`CheckReportKind.directoryURL`): ghi, liệt kê, đọc, xoá, tự dọn.
///
/// - Tự dọn: mỗi loại giữ `retainedCount` báo cáo mới nhất. Tên file là thời điểm bắt đầu lượt nên xếp theo tên = xếp
///   theo thời gian. Dọn sau mỗi lần ghi và một lần lúc mở app (`pruneAll`) — lần đó dọn luôn đống `legado_reports/`
///   tích từ trước 1.3.759 (trước đó không có code nào xoá).
/// - Lượt đang chạy (`markActive`) không bao giờ bị xoá: bộ chạy Legado ghi lại cùng file mỗi 50 nguồn, xoá xong thì file
///   lại hiện ra. App bị tắt giữa lượt ⇒ sổ trong RAM mất ⇒ file `state: running` còn lại xoá được bình thường.
/// - Chỉ đụng file `.json` nằm ngay trong thư mục của loại; mọi đường dẫn qua `validatePathSafety(_:kind:)` (cài lại
///   riêng ở owner này, như các owner khác).
/// - Hàm đồng bộ, gọi ngoài main: actor của bộ chạy, `Task.detached` của `CheckReportRepository` / lúc mở app.
enum CheckReportStore {
    static let retainedCount = 20

    enum StoreError: LocalizedError {
        case unsafePath
        case encodeFailed
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsafePath: return "Truy cập file ngoài thư mục báo cáo kiểm tra bị từ chối."
            case .encodeFailed: return "Không mã hoá được báo cáo kiểm tra."
            case .writeFailed(let message): return "Không ghi được báo cáo kiểm tra: \(message)"
            }
        }
    }

    /// Một file báo cáo trên đĩa.
    struct FileEntry: Sendable, Equatable {
        let kind: CheckReportKind
        let fileName: String
        let byteCount: Int64
    }

    /// Sổ các lượt đang chạy (`<kind>/<tên file>`), chỉ sống trong RAM.
    private final class ActiveRegistry: @unchecked Sendable {
        private let lock = NSLock()
        private var keys: Set<String> = []

        func insert(_ key: String) {
            lock.lock()
            keys.insert(key)
            lock.unlock()
        }

        func remove(_ key: String) {
            lock.lock()
            keys.remove(key)
            lock.unlock()
        }

        func contains(_ key: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return keys.contains(key)
        }
    }

    private static let registry = ActiveRegistry()

    // MARK: - Lượt đang chạy

    static func markActive(_ kind: CheckReportKind, startedAt: Date) {
        registry.insert(registryKey(kind, fileName(for: startedAt)))
    }

    static func markInactive(_ kind: CheckReportKind, startedAt: Date) {
        registry.remove(registryKey(kind, fileName(for: startedAt)))
    }

    static func isActive(_ kind: CheckReportKind, fileName: String) -> Bool {
        registry.contains(registryKey(kind, fileName))
    }

    private static func registryKey(_ kind: CheckReportKind, _ fileName: String) -> String {
        kind.rawValue + "/" + fileName
    }

    // MARK: - Ghi

    /// Ghi báo cáo (ghi đè file cùng lượt), dọn bớt bản cũ, trả đường dẫn **tương đối** so với `applicationSupport`
    /// (vd `legado_reports/20261021-153000.json`).
    @discardableResult
    static func write<Report: Encodable>(_ report: Report, kind: CheckReportKind, startedAt: Date) throws -> String {
        let name = fileName(for: startedAt)
        let root = kind.directoryURL
        let target = root.appendingPathComponent(name, isDirectory: false)
        try validatePathSafety(target, kind: kind)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(report) else { throw StoreError.encodeFailed }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: target, options: [.atomic])
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
        prune(kind)
        return kind.directoryName + "/" + name
    }

    // MARK: - Liệt kê / đọc

    /// File báo cáo của một loại, mới nhất trước.
    static func list(_ kind: CheckReportKind) -> [FileEntry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: kind.directoryURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { url -> FileEntry? in
            guard url.pathExtension.lowercased() == "json",
                  (try? validatePathSafety(url, kind: kind)) != nil else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { return nil }
            return FileEntry(kind: kind, fileName: url.lastPathComponent, byteCount: Int64(values?.fileSize ?? 0))
        }
        .sorted { $0.fileName > $1.fileName }
    }

    static func data(_ kind: CheckReportKind, fileName: String) -> Data? {
        guard let url = fileURL(kind, fileName: fileName) else { return nil }
        return try? Data(contentsOf: url)
    }

    // MARK: - Xoá

    /// `false` ⇒ lượt đang chạy, tên file không hợp lệ hoặc xoá lỗi.
    @discardableResult
    static func delete(_ kind: CheckReportKind, fileName: String) -> Bool {
        guard !isActive(kind, fileName: fileName), let url = fileURL(kind, fileName: fileName) else { return false }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            AppLogger.shared.log("❌ [CheckReport] Không xoá được \(kind.directoryName)/\(fileName): \(error.localizedDescription)")
            return false
        }
    }

    /// Xoá mọi báo cáo của loại, trừ lượt đang chạy. Trả số file đã xoá.
    @discardableResult
    static func deleteAll(_ kind: CheckReportKind) -> Int {
        list(kind).reduce(0) { count, entry in delete(kind, fileName: entry.fileName) ? count + 1 : count }
    }

    /// Giữ `keeping` báo cáo mới nhất, xoá phần còn lại (trừ lượt đang chạy). Trả số file đã xoá.
    @discardableResult
    static func prune(_ kind: CheckReportKind, keeping: Int = retainedCount) -> Int {
        let entries = list(kind)
        guard entries.count > keeping else { return 0 }
        return entries.dropFirst(keeping).reduce(0) { count, entry in
            delete(kind, fileName: entry.fileName) ? count + 1 : count
        }
    }

    /// Lúc mở app: dọn cả hai loại theo luật giữ `retainedCount` bản mới nhất.
    static func pruneAll() {
        for kind in CheckReportKind.allCases {
            let removed = prune(kind)
            if removed > 0 {
                AppLogger.shared.log("🧹 [CheckReport] Tự dọn \(removed) báo cáo \(kind.title) cũ (giữ \(retainedCount) mới nhất)")
            }
        }
    }

    // MARK: - Tên file / đường dẫn

    /// `yyyyMMdd-HHmmss.json` theo thời điểm bắt đầu lượt.
    static func fileName(for date: Date) -> String {
        fileNameFormatter().string(from: date) + ".json"
    }

    /// Ngược của `fileName(for:)` — dùng khi file hỏng không đọc được `startedAt`.
    static func date(fromFileName fileName: String) -> Date? {
        let stem = (fileName as NSString).deletingPathExtension
        return fileNameFormatter().date(from: stem)
    }

    private static func fileNameFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }

    private static func fileURL(_ kind: CheckReportKind, fileName: String) -> URL? {
        guard !fileName.isEmpty, !fileName.contains("/"), fileName.lowercased().hasSuffix(".json") else { return nil }
        let url = kind.directoryURL.appendingPathComponent(fileName, isDirectory: false)
        return (try? validatePathSafety(url, kind: kind)) != nil ? url : nil
    }

    /// Đường dẫn phải nằm **ngay trong** thư mục của loại (sau khi chuẩn hoá `.`/`..`).
    private static func validatePathSafety(_ targetURL: URL, kind: CheckReportKind) throws {
        let root = comparableComponents(kind.directoryURL)
        let target = comparableComponents(targetURL)
        guard target.count == root.count + 1, target.starts(with: root) else {
            throw StoreError.unsafePath
        }
    }

    /// Bỏ tiền tố `/private` (iOS: `/var` ↔ `/private/var` tuỳ đường dẫn đã tồn tại hay chưa — xem
    /// `LegadoCorpusReportShare.comparableComponents`).
    private static func comparableComponents(_ url: URL) -> [String] {
        var parts = url.standardizedFileURL.pathComponents
        if parts.count > 1, parts[0] == "/", parts[1] == "private" {
            parts.remove(at: 1)
        }
        return parts
    }
}
