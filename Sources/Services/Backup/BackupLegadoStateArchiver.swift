import Foundation

/// Sao lưu / khôi phục `applicationSupport/legado_state/` — trạng thái của nguồn Legado — **trừ** cookie và mọi thứ
/// dính đăng nhập.
///
/// Archive:
/// - `legado_state/books/<sha256(bookId)>.json` — sidecar trạng thái truyện (`LegadoBookStateStore`: `tocUrl`, thông
///   tin, biến sách/chương), chỉ cho truyện có trong `library/books.json`. Đi kèm nhóm `.books`.
/// - `legado_state/sources/<sha256(bookSourceUrl)>.json` — trạng thái nguồn của engine (`LegadoFileStateStore`: biến
///   nguồn, `source.put`, `cache.*`) dựng lại **sạch**: chỉ chép `variable`/`values`/`cache`, mọi trường khác (cookie, và
///   bất kỳ trường nào kho thêm sau này) giữ mặc định rỗng. Đi kèm nhóm `.extensions`.
/// - Không sao lưu: `jslib/` (tải lại được), `device.json` (định danh máy), thông tin/header đăng nhập (Keychain).
///
/// Khôi phục là **gộp, giữ bản của máy** (nguyên tắc chung của phân hệ): sidecar chỉ ghi khi máy chưa có file; trạng
/// thái nguồn gộp theo **từng khoá** qua API của kho (khoá máy đã có thì giữ) để bộ nhớ đệm của kho thấy ngay và lượt
/// ghi gom của nó không đè mất. Không thêm `BackupScope` (rawValue nằm trong manifest — bản app cũ sẽ đọc lỗi).
enum BackupLegadoStateArchiver {
    static let booksFolder = "legado_state/books"
    static let sourcesFolder = "legado_state/sources"

    struct Report: Sendable {
        var bookFiles = 0
        var sourceStates = 0
        var errors: [String] = []
    }

    private typealias SourceState = LegadoFileStateStore.SourceState

    static var rootURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("legado_state", isDirectory: true)
    }

    private static var sourcesDirectory: URL {
        rootURL.appendingPathComponent("sources", isDirectory: true)
    }

    // MARK: - Xuất

    /// Ghi vào staging; trả số file đã ghi. Lỗi từng file chỉ log — không làm hỏng cả lượt sao lưu.
    @discardableResult
    static func stage(bookIds: [String], includeSources: Bool, into staging: URL) -> Int {
        var books = 0
        var sources = 0
        for bookId in Set(bookIds) {
            let name = bookId.sha256() + ".json"
            let file = rootURL.appendingPathComponent(name)
            guard (try? validatePathSafety(for: file)) != nil, isRegularFile(file) else { continue }
            do {
                try BackupZipArchive.stage(fileAt: file, entryName: "\(booksFolder)/\(name)", in: staging)
                books += 1
            } catch {
                AppLogger.shared.log("❌ [Backup] Không gom được trạng thái truyện Legado: \(error.localizedDescription)")
            }
        }
        if includeSources {
            for file in sourceFiles() {
                guard let state = readSourceState(at: file), let data = encodedClean(state) else { continue }
                do {
                    try BackupZipArchive.stage(data: data, entryName: "\(sourcesFolder)/\(file.lastPathComponent)", in: staging)
                    sources += 1
                } catch {
                    AppLogger.shared.log("❌ [Backup] Không gom được trạng thái nguồn Legado: \(error.localizedDescription)")
                }
            }
        }
        if books + sources > 0 {
            AppLogger.shared.log("💾 [Backup] Trạng thái Legado: \(books) truyện, \(sources) nguồn (đã bỏ cookie)")
        }
        return books + sources
    }

    // MARK: - Khôi phục

    static func restore(from directory: URL, bookIds: [String], includeSources: Bool) -> Report {
        var report = Report()
        restoreBookStates(from: directory, bookIds: bookIds, into: &report)
        if includeSources {
            restoreSourceStates(from: directory, into: &report)
        }
        if report.bookFiles + report.sourceStates > 0 {
            AppLogger.shared.log("♻️ [Restore] Trạng thái Legado: \(report.bookFiles) truyện, \(report.sourceStates) nguồn")
        }
        return report
    }

    private static func restoreBookStates(from directory: URL, bookIds: [String], into report: inout Report) {
        for bookId in Set(bookIds) {
            let name = bookId.sha256() + ".json"
            guard let data = BackupZipArchive.readStaged(entryName: "\(booksFolder)/\(name)", in: directory),
                  (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { continue }
            let target = rootURL.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: target.path) else { continue }
            do {
                try validatePathSafety(for: target)
                try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
                try data.write(to: target, options: [.atomic])
                report.bookFiles += 1
            } catch {
                report.errors.append("Trạng thái truyện Legado: \(error.localizedDescription)")
            }
        }
    }

    /// Gộp từng khoá vào `LegadoFileStateStore.shared` cho nguồn **đang cài** (khoá kho = `bookSourceUrl` nguyên văn,
    /// tên file = sha256 của khoá đó). Nguồn không còn trên máy ⇒ bỏ qua.
    private static func restoreSourceStates(from directory: URL, into report: inout Report) {
        let staged = directory.appendingPathComponent(sourcesFolder, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: staged.path), !names.isEmpty else { return }
        let keysByDigest = installedSourceKeys()
        let store = LegadoFileStateStore.shared
        let now = Date().timeIntervalSince1970
        for name in names.sorted() where name.hasSuffix(".json") {
            guard let key = keysByDigest[String(name.dropLast(5))],
                  let data = BackupZipArchive.readStaged(entryName: "\(sourcesFolder)/\(name)", in: directory),
                  let state = try? JSONDecoder().decode(SourceState.self, from: data) else { continue }
            var changed = false
            if !state.variable.isEmpty, store.sourceVariable(sourceKey: key).isEmpty {
                store.setSourceVariable(state.variable, sourceKey: key)
                changed = true
            }
            for (field, value) in state.values where store.sourceValue(forKey: field, sourceKey: key) == nil {
                store.setSourceValue(value, forKey: field, sourceKey: key)
                changed = true
            }
            for (field, entry) in state.cache where store.cacheValue(forKey: field, sourceKey: key) == nil {
                let ttl: TimeInterval? = entry.expires.map { $0 - now }
                if let ttl, ttl <= 0 { continue }
                store.setCacheValue(entry.value, forKey: field, sourceKey: key, ttl: ttl)
                changed = true
            }
            if changed { report.sourceStates += 1 }
        }
    }

    /// sha256(`bookSourceUrl` nguyên văn) → `bookSourceUrl`, cho mọi nguồn Legado đang cài (đọc `source.json`).
    private static func installedSourceKeys() -> [String: String] {
        var table: [String: String] = [:]
        for ext in ExtensionLibraryRepository.installedSnapshot() where LegadoSourceIdentity.isLegado(ext) {
            guard let source = try? LegadoSourceStore.loadSource(localPath: ext.localPath) else { continue }
            table[source.bookSourceUrl.sha256()] = source.bookSourceUrl
        }
        return table
    }

    // MARK: - Dấu vân tay

    /// Phần `legado_state/` của dấu vân tay sao lưu tự động (`BackupLibraryFingerprint`): sidecar theo tên + kích thước
    /// + mốc sửa; trạng thái nguồn theo **nội dung** biến nguồn + `source.put`. Cố ý không băm cookie và `cache` (đổi
    /// liên tục khi duyệt nguồn — cùng lý do `localStorage` của tiện ích không được băm); chúng vẫn đi theo lượt sao lưu
    /// kế tiếp do thay đổi khác.
    static func fingerprintData(bookIds: [String], includeSources: Bool) -> Data {
        var lines: [String] = []
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        for bookId in Set(bookIds).sorted() {
            let name = bookId.sha256() + ".json"
            guard let values = try? rootURL.appendingPathComponent(name).resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            let modified = values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
            lines.append("b|\(name)|\(values.fileSize ?? 0)|\(modified)")
        }
        if includeSources {
            for file in sourceFiles() {
                guard let state = readSourceState(at: file) else { continue }
                let values = state.values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
                lines.append("s|\(file.lastPathComponent)|\(state.variable)|" + values.joined(separator: "\u{1}"))
            }
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    // MARK: - File

    /// `sources/*.json` (tên = 64 hex), đã sắp xếp.
    private static func sourceFiles() -> [URL] {
        let directory = sourcesDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.sorted()
            .filter { $0.hasSuffix(".json") && $0.count == 69 }
            .map { directory.appendingPathComponent($0) }
            .filter { (try? validatePathSafety(for: $0)) != nil }
    }

    private static func readSourceState(at file: URL) -> SourceState? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(SourceState.self, from: data)
    }

    /// Bản sạch: chỉ biến nguồn, `source.put`, `cache` còn hạn. `nil` khi không còn gì để lưu.
    private static func encodedClean(_ state: SourceState) -> Data? {
        let now = Date().timeIntervalSince1970
        var clean = SourceState()
        clean.variable = state.variable
        clean.values = state.values
        clean.cache = state.cache.filter { $0.value.expires.map { $0 > now } ?? true }
        guard !clean.variable.isEmpty || !clean.values.isEmpty || !clean.cache.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(clean)
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    /// Đường dẫn phải nằm **trong** `legado_state/` (sau khi chuẩn hoá và giải symlink).
    private static func validatePathSafety(for targetURL: URL) throws {
        let canonicalRoot = rootURL.standardized.resolvingSymlinksInPath()
        let canonicalTarget = targetURL.standardized.resolvingSymlinksInPath()
        guard canonicalTarget.pathComponents.count > canonicalRoot.pathComponents.count,
              canonicalTarget.pathComponents.starts(with: canonicalRoot.pathComponents) else {
            throw NSError(domain: "SecurityError", code: 403,
                          userInfo: [NSLocalizedDescriptionKey: "Truy cập file ngoài thư mục legado_state bị từ chối."])
        }
    }
}
