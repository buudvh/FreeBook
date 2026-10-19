import Foundation

/// Tải bộ lọc quảng cáo và là chủ **duy nhất** của `adblock/filters/<id>.txt` + `adblock/filters_meta.json`.
///
/// - Tải bằng URLSession (timeout 60 s), xác nhận có dòng `! Title:` rồi mới ghi nguyên tử đè file cũ.
/// - Hạn dùng đọc từ dòng `! Expires: N days` của chính bộ lọc (thiếu ⇒ 5 ngày).
/// - Lỗi mạng/HTTP/nội dung ⇒ **giữ file cũ**, ghi `lastError`, log `❌`. Không có vòng retry: lần mở app sau
///   (`AdBlockRuleListProvider.warmUp`) hoặc nút "Cập nhật ngay" thử lại.
/// - Chưa từng tải ⇒ nguồn là bản đóng gói (`adguard-<id>.txt` trong bundle), ngày lấy từ
///   `adblock_bundled_meta.json`.
///
/// Không biên dịch gì — `AdBlockRuleListProvider` điều phối chuyển đổi/biên dịch và gọi `recordCompiled` để lưu
/// khoá biên dịch vào meta (cùng file, nên mọi ghi meta đi qua actor này).
actor AdBlockUpdateWorker {
    static let shared = AdBlockUpdateWorker()

    /// Meta một bộ trong `filters_meta.json` (khoá = id dạng chuỗi).
    struct FilterMeta: Codable, Equatable, Sendable {
        var downloadedAt: Date?
        var expiresSeconds: Double?
        /// sha256 của file đã tải.
        var checksum: String?
        var sourceRuleCount: Int?
        var safariRuleCount: Int?
        /// sha256 của file nguồn (tải hoặc đóng gói) đã biên dịch vào `WKContentRuleListStore`.
        var compiledSourceChecksum: String?
        /// sha256 của JSON luật WebKit đã biên dịch.
        var compiledJSONChecksum: String?
        /// `AdBlockRuleCompiler.compilerKey` lúc biên dịch (đổi thư viện / phiên bản Safari ⇒ biên dịch lại).
        var compilerKey: String?
        var lastError: String?
        var lastErrorAt: Date?
    }

    /// Nội dung để biên dịch: file đã tải, nếu không có thì bản đóng gói.
    struct FilterSource: Sendable {
        let text: String
        /// sha256 của đúng byte nguồn.
        let checksum: String
        let updatedAt: Date?
        let isBundled: Bool
    }

    /// Dữ liệu để dựng `AdBlockFilterStatus` mà không cần biên dịch.
    struct StatusSeed: Equatable, Sendable {
        let safariRuleCount: Int?
        let updatedAt: Date?
        let lastError: String?
        /// Có nguồn và nguồn đó đã từng được biên dịch (rule list còn trong store của WebKit).
        let hasCompiledData: Bool
    }

    enum DownloadOutcome: Equatable, Sendable {
        /// Nội dung khác bản đang có (hoặc trước đó chỉ có bản đóng gói) ⇒ cần biên dịch lại.
        case updated
        /// Tải được nhưng trùng checksum bản đã tải — chỉ làm mới hạn dùng.
        case unchanged
        case failed(String)
    }

    private struct BundledMeta: Decodable {
        let downloadedAt: Date
    }

    static let defaultExpiresSeconds: TimeInterval = 5 * 24 * 60 * 60
    private static let requestTimeout: TimeInterval = 60

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = AdBlockUpdateWorker.requestTimeout
        // Base ~3,3 MB: cho phép mạng chậm tải hết, nhưng không treo vô hạn.
        config.timeoutIntervalForResource = AdBlockUpdateWorker.requestTimeout * 5
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private var metaCache: [String: FilterMeta]?
    private var bundledMetaLoaded = false
    private var bundledDownloadedAt: Date?

    private init() {}

    // MARK: - Đọc

    func meta(id: Int) -> FilterMeta? {
        allMeta()[Self.key(id)]
    }

    /// Các bộ trong `ids` cần tải: `force`, hoặc file đã tải quá hạn, hoặc chưa tải mà bản đóng gói đã quá 5 ngày
    /// (bộ không đóng gói mà chưa tải ⇒ luôn cần). Giữ thứ tự của `ids`.
    func filtersDue(_ ids: [Int], force: Bool, now: Date = Date()) -> [Int] {
        guard !force else { return ids }
        return ids.filter { isExpired(id: $0, now: now) }
    }

    func hasSource(for filter: AdBlockFilter) -> Bool {
        hasDownloadedFile(id: filter.id) || bundledURL(for: filter) != nil
    }

    func source(for filter: AdBlockFilter) -> FilterSource? {
        let fileURL = AdBlockPaths.filterFile(id: filter.id)
        if let data = try? Data(contentsOf: fileURL), !data.isEmpty {
            let modifiedAt = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return FilterSource(
                text: String(decoding: data, as: UTF8.self),
                checksum: data.sha256Hex(),
                updatedAt: meta(id: filter.id)?.downloadedAt ?? modifiedAt,
                isBundled: false
            )
        }
        guard let url = bundledURL(for: filter), let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return FilterSource(
            text: String(decoding: data, as: UTF8.self),
            checksum: data.sha256Hex(),
            updatedAt: bundledDate(),
            isBundled: true
        )
    }

    func statusSeed(for filter: AdBlockFilter) -> StatusSeed {
        let entry = meta(id: filter.id)
        let downloaded = hasDownloadedFile(id: filter.id)
        let bundled = bundledURL(for: filter) != nil
        let updatedAt: Date? = downloaded ? entry?.downloadedAt : (bundled ? bundledDate() : nil)
        return StatusSeed(
            safariRuleCount: entry?.safariRuleCount,
            updatedAt: updatedAt,
            lastError: entry?.lastError,
            hasCompiledData: (downloaded || bundled) && entry?.compiledSourceChecksum != nil
        )
    }

    // MARK: - Ghi

    /// Tải một bộ. Không ném lỗi: kết quả lỗi đã được ghi vào meta + log `❌`.
    func download(_ filter: AdBlockFilter) async -> DownloadOutcome {
        let id = filter.id
        let request = URLRequest(
            url: filter.subscriptionURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: Self.requestTimeout
        )
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw DownloadError.http(http.statusCode)
            }
            let text = String(decoding: data, as: UTF8.self)
            guard Self.hasTitleLine(text) else { throw DownloadError.notAFilter }
            guard AdBlockPaths.ensureDirectory(AdBlockPaths.filtersDirectory) else { throw DownloadError.io }
            let previousChecksum = hasDownloadedFile(id: id) ? meta(id: id)?.checksum : nil
            // `.atomic`: Foundation ghi ra file tạm cạnh đích rồi đổi tên — file cũ còn nguyên nếu ghi hỏng giữa chừng.
            try data.write(to: AdBlockPaths.filterFile(id: id), options: .atomic)

            let checksum = data.sha256Hex()
            // Đọc lại meta SAU `await`: actor có thể đã ghi meta khác (recordCompiled) trong lúc chờ mạng.
            var entry = meta(id: id) ?? FilterMeta()
            entry.downloadedAt = Date()
            entry.expiresSeconds = Self.expiresSeconds(in: text) ?? Self.defaultExpiresSeconds
            entry.checksum = checksum
            entry.lastError = nil
            entry.lastErrorAt = nil
            setMeta(entry, id: id)
            AppLogger.shared.log("🛡️ [AdBlock] Đã tải bộ lọc \(id): \(data.count) byte")
            return previousChecksum == checksum ? .unchanged : .updated
        } catch {
            let message = Self.describe(error)
            var entry = meta(id: id) ?? FilterMeta()
            entry.lastError = message
            entry.lastErrorAt = Date()
            setMeta(entry, id: id)
            AppLogger.shared.log("❌ 🛡️ [AdBlock] Tải bộ lọc \(id) thất bại (giữ bản cũ): \(message)")
            return .failed(message)
        }
    }

    /// Lưu khoá biên dịch sau khi `WKContentRuleListStore` biên dịch/tra thành công.
    func recordCompiled(
        id: Int,
        sourceChecksum: String,
        jsonChecksum: String,
        compilerKey: String,
        sourceRuleCount: Int,
        safariRuleCount: Int
    ) {
        var entry = meta(id: id) ?? FilterMeta()
        entry.compiledSourceChecksum = sourceChecksum
        entry.compiledJSONChecksum = jsonChecksum
        entry.compilerKey = compilerKey
        entry.sourceRuleCount = sourceRuleCount
        entry.safariRuleCount = safariRuleCount
        setMeta(entry, id: id)
    }

    // MARK: - Hạn dùng

    private func isExpired(id: Int, now: Date) -> Bool {
        if hasDownloadedFile(id: id) {
            let entry = meta(id: id)
            guard let downloadedAt = entry?.downloadedAt else { return true }
            let expires = entry?.expiresSeconds ?? Self.defaultExpiresSeconds
            let age = now.timeIntervalSince(downloadedAt)
            // Đồng hồ máy từng chạy nhanh (ngày tải nằm ở tương lai) ⇒ coi như quá hạn, không kẹt mãi.
            return age >= expires || age < -86_400
        }
        guard let filter = AdBlockFilter.filter(id: id), bundledURL(for: filter) != nil,
              let bundledAt = bundledDate() else { return true }
        return now.timeIntervalSince(bundledAt) >= Self.defaultExpiresSeconds
    }

    /// `! Expires: 5 days (update frequency)` / `! Expires: 12 hours`. Kẹp trong 1 giờ … 30 ngày.
    static func expiresSeconds(in text: String) -> TimeInterval? {
        for line in headerLines(text) {
            let lower = line.lowercased()
            guard let range = lower.range(of: "expires:") else { continue }
            let rest = lower[range.upperBound...].trimmingCharacters(in: .whitespaces)
            let digits = rest.prefix(while: \.isNumber)
            guard let value = Double(digits), value > 0 else { return nil }
            let unit = rest.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
            let seconds = unit.hasPrefix("h") ? value * 3_600 : value * 86_400
            return min(max(seconds, 3_600), 30 * 86_400)
        }
        return nil
    }

    static func hasTitleLine(_ text: String) -> Bool {
        headerLines(text).contains { $0.hasPrefix("! Title:") }
    }

    /// 60 dòng đầu file (header AdGuard nằm ở đây). `isNewline` tách được cả `\r\n` — file máy chủ trả về là CRLF.
    private static func headerLines(_ text: String) -> [Substring] {
        var head = text.prefix(16_384)
        if head.hasPrefix("\u{FEFF}") { head = head.dropFirst() }
        return Array(head.split(whereSeparator: \.isNewline).prefix(60))
    }

    // MARK: - File

    private func hasDownloadedFile(id: Int) -> Bool {
        FileManager.default.fileExists(atPath: AdBlockPaths.filterFile(id: id).path)
    }

    private func bundledURL(for filter: AdBlockFilter) -> URL? {
        guard let name = filter.bundledResourceName else { return nil }
        return Bundle.main.url(forResource: name, withExtension: "txt")
    }

    private func bundledDate() -> Date? {
        if bundledMetaLoaded { return bundledDownloadedAt }
        bundledMetaLoaded = true
        guard let url = Bundle.main.url(forResource: "adblock_bundled_meta", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            AppLogger.shared.log("❌ 🛡️ [AdBlock] Thiếu adblock_bundled_meta.json trong bundle")
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        bundledDownloadedAt = (try? decoder.decode(BundledMeta.self, from: data))?.downloadedAt
        return bundledDownloadedAt
    }

    private func allMeta() -> [String: FilterMeta] {
        if let metaCache { return metaCache }
        var loaded: [String: FilterMeta] = [:]
        if let data = try? Data(contentsOf: AdBlockPaths.metaFile) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([String: FilterMeta].self, from: data) {
                loaded = decoded
            } else {
                // Hỏng meta ⇒ mọi bộ coi như quá hạn/chưa biên dịch: tự lành ở lượt tải/biên dịch kế tiếp.
                AppLogger.shared.log("❌ 🛡️ [AdBlock] filters_meta.json hỏng, bỏ qua")
            }
        }
        metaCache = loaded
        return loaded
    }

    private func setMeta(_ meta: FilterMeta, id: Int) {
        var all = allMeta()
        all[Self.key(id)] = meta
        metaCache = all
        guard AdBlockPaths.ensureDirectory(AdBlockPaths.rootDirectory) else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(all).write(to: AdBlockPaths.metaFile, options: .atomic)
        } catch {
            AppLogger.shared.log("❌ 🛡️ [AdBlock] Không ghi được filters_meta.json: \(error.localizedDescription)")
        }
    }

    private static func key(_ id: Int) -> String { String(id) }

    // MARK: - Lỗi

    private enum DownloadError: Error {
        case http(Int)
        case notAFilter
        case io
    }

    private static func describe(_ error: Error) -> String {
        guard let downloadError = error as? DownloadError else { return error.localizedDescription }
        switch downloadError {
        case .http(let code): return "HTTP \(code)"
        case .notAFilter: return "Nội dung tải về không phải bộ lọc"
        case .io: return "Không tạo được thư mục lưu bộ lọc"
        }
    }
}
