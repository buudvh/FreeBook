import Foundation
import CryptoKit

/// Bản cài mặc định của `LegadoPersistentStore`: file JSON nhỏ dưới `applicationSupport/legado_state/`.
///
/// ```
/// legado_state/
///   sources/<sha256(bookSourceUrl)>.json   biến nguồn, source.put, cache.*, cookie
///   jslib/<sha256(url)>.js                  bản tải của jsLib dạng {tên: url}
///   device.json                             java.androidId()
/// ```
///
/// Trạng thái nguồn nạp lười vào bộ nhớ; mọi lần ghi đánh dấu "bẩn" rồi gom ghi sau 0,5 giây trên queue nền (ghi
/// nguyên tử). Mọi thao tác file qua `validatePathSafety(for:)` (cài lại riêng theo quy ước repo).
final class LegadoFileStateStore: LegadoPersistentStore, @unchecked Sendable {
    static let shared = LegadoFileStateStore()

    struct SourceState: Codable {
        struct CacheEntry: Codable {
            var value: String
            var expires: Double?
        }

        var variable = ""
        var values: [String: String] = [:]
        var cache: [String: CacheEntry] = [:]
        var cookies: [LegadoStoredCookie] = []
        /// `infoMap` của khám phá động (đợt 2). **Optional** để file của bản trước (không có khoá) vẫn decode được.
        var infoMap: [String: String]?
    }

    private let rootURL: URL
    private let lock = NSLock()
    private var states: [String: SourceState] = [:]
    private var dirtyKeys: Set<String> = []
    private var writeScheduled = false
    private var deviceId: String?
    private let writeQueue = DispatchQueue(label: "FreeBook.LegadoState", qos: .utility)

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.rootURL = base.appendingPathComponent("legado_state", isDirectory: true)
        }
    }

    // MARK: - LegadoPersistentStore

    func sourceVariable(sourceKey: String) -> String {
        read(sourceKey) { $0.variable }
    }

    func setSourceVariable(_ value: String, sourceKey: String) {
        mutate(sourceKey) { $0.variable = value }
    }

    func sourceValue(forKey key: String, sourceKey: String) -> String? {
        read(sourceKey) { $0.values[key] }
    }

    func setSourceValue(_ value: String, forKey key: String, sourceKey: String) {
        mutate(sourceKey) { $0.values[key] = value }
    }

    func cacheValue(forKey key: String, sourceKey: String) -> String? {
        let now = Date().timeIntervalSince1970
        return read(sourceKey) { state -> String? in
            guard let entry = state.cache[key] else { return nil }
            if let expires = entry.expires, expires <= now { return nil }
            return entry.value
        }
    }

    func setCacheValue(_ value: String, forKey key: String, sourceKey: String, ttl: TimeInterval?) {
        let expires = ttl.map { Date().timeIntervalSince1970 + $0 }
        mutate(sourceKey) { $0.cache[key] = SourceState.CacheEntry(value: value, expires: expires) }
    }

    func removeCacheValue(forKey key: String, sourceKey: String) {
        mutate(sourceKey) { $0.cache.removeValue(forKey: key) }
    }

    func cookies(sourceKey: String) -> [LegadoStoredCookie] {
        read(sourceKey) { $0.cookies }
    }

    func setCookies(_ cookies: [LegadoStoredCookie], sourceKey: String) {
        mutate(sourceKey) { $0.cookies = cookies }
    }

    func exploreInfo(sourceKey: String) -> [String: String] {
        read(sourceKey) { $0.infoMap ?? [:] }
    }

    func setExploreValue(_ value: String?, forKey key: String, sourceKey: String) {
        mutate(sourceKey) { state in
            var info = state.infoMap ?? [:]
            info[key] = value
            state.infoMap = info.isEmpty ? nil : info
        }
    }

    func libraryScript(url: String) -> String? {
        let fileURL = rootURL.appendingPathComponent("jslib", isDirectory: true)
            .appendingPathComponent(Self.sha256(url) + ".js")
        guard (try? validatePathSafety(for: fileURL)) != nil else { return nil }
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    func setLibraryScript(_ script: String, url: String) {
        let directory = rootURL.appendingPathComponent("jslib", isDirectory: true)
        let fileURL = directory.appendingPathComponent(Self.sha256(url) + ".js")
        writeQueue.async { [self] in
            do {
                try validatePathSafety(for: fileURL)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data(script.utf8).write(to: fileURL, options: .atomic)
            } catch {
                AppLogger.shared.log("❌ [Legado] Không lưu được jsLib: \(error.localizedDescription)")
            }
        }
    }

    func deviceIdentifier() -> String {
        lock.lock()
        defer { lock.unlock() }
        if let deviceId { return deviceId }
        let fileURL = rootURL.appendingPathComponent("device.json")
        if (try? validatePathSafety(for: fileURL)) != nil,
           let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([String: String].self, from: data),
           let value = stored["androidId"], !value.isEmpty {
            deviceId = value
            return value
        }
        let value = (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        deviceId = value
        do {
            try validatePathSafety(for: fileURL)
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try JSONEncoder().encode(["androidId": value]).write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.shared.log("❌ [Legado] Không lưu được androidId: \(error.localizedDescription)")
        }
        return value
    }

    // MARK: - Trạng thái theo nguồn

    private func read<T>(_ sourceKey: String, _ body: (SourceState) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(loadedState(sourceKey))
    }

    private func mutate(_ sourceKey: String, _ body: (inout SourceState) -> Void) {
        lock.lock()
        var state = loadedState(sourceKey)
        body(&state)
        states[sourceKey] = state
        dirtyKeys.insert(sourceKey)
        let shouldSchedule = !writeScheduled
        writeScheduled = true
        lock.unlock()
        if shouldSchedule {
            writeQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.flush() }
        }
    }

    /// Gọi khi đang giữ `lock`.
    private func loadedState(_ sourceKey: String) -> SourceState {
        if let state = states[sourceKey] { return state }
        var state = SourceState()
        let fileURL = stateURL(sourceKey)
        if (try? validatePathSafety(for: fileURL)) != nil,
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(SourceState.self, from: data) {
            state = decoded
            let now = Date().timeIntervalSince1970
            state.cache = state.cache.filter { $0.value.expires.map { $0 > now } ?? true }
        }
        states[sourceKey] = state
        return state
    }

    /// Ghi mọi nguồn "bẩn" xuống đĩa (chạy trên `writeQueue`).
    func flush() {
        lock.lock()
        let keys = dirtyKeys
        dirtyKeys.removeAll()
        writeScheduled = false
        let snapshots = keys.compactMap { key in states[key].map { (key, $0) } }
        lock.unlock()
        guard !snapshots.isEmpty else { return }
        let directory = rootURL.appendingPathComponent("sources", isDirectory: true)
        for (key, state) in snapshots {
            let fileURL = stateURL(key)
            do {
                try validatePathSafety(for: fileURL)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
            } catch {
                AppLogger.shared.log("❌ [Legado] Không lưu được trạng thái nguồn: \(error.localizedDescription)")
            }
        }
    }

    private func stateURL(_ sourceKey: String) -> URL {
        rootURL.appendingPathComponent("sources", isDirectory: true)
            .appendingPathComponent(Self.sha256(sourceKey) + ".json")
    }

    // MARK: - An toàn đường dẫn

    /// Đường dẫn phải nằm **trong** `legado_state/` (sau khi chuẩn hoá và giải symlink).
    private func validatePathSafety(for targetURL: URL) throws {
        let canonicalRoot = rootURL.standardized.resolvingSymlinksInPath()
        let canonicalTarget = targetURL.standardized.resolvingSymlinksInPath()
        guard canonicalTarget.pathComponents.count > canonicalRoot.pathComponents.count,
              canonicalTarget.pathComponents.starts(with: canonicalRoot.pathComponents) else {
            throw NSError(domain: "SecurityError", code: 403,
                          userInfo: [NSLocalizedDescriptionKey: "Truy cập file ngoài thư mục legado_state bị từ chối."])
        }
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
