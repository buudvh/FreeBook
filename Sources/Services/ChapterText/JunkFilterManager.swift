import Foundation
import Combine

public struct JunkFilterRule: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var pattern: String
    public var replacement: String
    public var isRegex: Bool
    public var isEnabled: Bool

    public init(id: String = UUID().uuidString, pattern: String, replacement: String = "", isRegex: Bool = false, isEnabled: Bool = true) {
        self.id = id
        self.pattern = pattern
        self.replacement = replacement
        self.isRegex = isRegex
        self.isEnabled = isEnabled
    }

    enum CodingKeys: String, CodingKey {
        case id, pattern, replacement, isRegex, isEnabled
        case word, regex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        
        if let p = try container.decodeIfPresent(String.self, forKey: .pattern) {
            self.pattern = p
        } else if let w = try container.decodeIfPresent(String.self, forKey: .word) {
            self.pattern = w
        } else {
            self.pattern = ""
        }
        
        self.replacement = try container.decodeIfPresent(String.self, forKey: .replacement) ?? ""
        
        if let r = try container.decodeIfPresent(Bool.self, forKey: .isRegex) {
            self.isRegex = r
        } else if let r = try container.decodeIfPresent(Bool.self, forKey: .regex) {
            self.isRegex = r
        } else {
            self.isRegex = false
        }
        
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(replacement, forKey: .replacement)
        try container.encode(isRegex, forKey: .isRegex)
        try container.encode(isEnabled, forKey: .isEnabled)
    }
}

public final class JunkFilterManager: ObservableObject {
    public static let shared = JunkFilterManager()

    @MainActor @Published public private(set) var rules: [JunkFilterRule] = []
    private let lock = NSLock()
    /// Quy tắc đang bật đã biên dịch (regex + điều kiện cần để khớp, `JunkFilterCompiledRule`).
    private nonisolated(unsafe) var activeRulesCache: [JunkFilterCompiledRule] = []
    /// Cùng bộ quy tắc nhưng mẫu + chữ thay đã chuyển phồn → giản — cho chữ đã qua bước chuyển của
    /// `ChineseTextPipeline.normalizeChapter` (1.3.846): mẫu viết bằng chữ phồn vẫn khớp. Dựng lười một lần sau mỗi lần
    /// đổi quy tắc (`nil` = chưa dựng), cùng lock với `activeRulesCache`.
    private nonisolated(unsafe) var convertedRulesCache: [JunkFilterCompiledRule]?
    /// Tăng mỗi lần bộ quy tắc đổi (cùng lock) — kết quả tính bằng bộ cũ không được ghi vào cache kết quả.
    private nonisolated(unsafe) var rulesGeneration = 0
    /// Kết quả lọc theo **đúng chuỗi vào** (1.3.970): một chương bị lọc nhiều lần với cùng chuỗi — Reader và TTS cùng
    /// `normalizeChapter` một nội dung, lưu chương (`upsert`) lọc lại đúng chuỗi Reader nhận, quét tên riêng AI chạy lại
    /// đọc lại cùng chương từ file. Lọc là hàm thuần của (chuỗi vào, bộ quy tắc) ⇒ trả lại kết quả cũ y hệt; đổi quy tắc
    /// thì xoá. Hai bộ: chữ thô / chữ đã chuyển phồn → giản (bộ mẫu khác nhau).
    private let resultCache = JunkFilterManager.makeResultCache()
    private let convertedResultCache = JunkFilterManager.makeResultCache()
    /// Chuỗi dài hơn mức này (vd chương TXT không tách) không giữ trong cache.
    private static let maxCachedLength = 200_000

    private var rulesFileURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let directory = paths[0].appendingPathComponent("translate", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        return directory.appendingPathComponent("junk_filter_rules.json")
    }

    private init() {
        Task { @MainActor in
            self.loadRules()
        }
    }

    // MARK: - Persistence

    @MainActor
    public func loadRules() {
        let url = rulesFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            self.rules = []
            updateCache([])
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder().decode([JunkFilterRule].self, from: data)
            self.rules = loaded
            updateCache(loaded)
        } catch {
            AppLogger.shared.log("❌ [JunkFilterManager] Lỗi nạp quy tắc lọc rác: \(error.localizedDescription)")
            self.rules = []
            updateCache([])
        }
    }

    @MainActor
    private func saveRules() {
        let snapshot = rules
        updateCache(snapshot)
        let url = rulesFileURL
        Task.detached(priority: .background) {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                AppLogger.shared.log("❌ [JunkFilterManager] Lỗi lưu quy tắc lọc rác: \(error.localizedDescription)")
            }
        }
    }

    private func updateCache(_ list: [JunkFilterRule]) {
        // Biên dịch regex + điều kiện khớp một lần khi danh sách quy tắc đổi; regex lỗi bị bỏ qua như `try?` cũ.
        let compiled = list.filter { $0.isEnabled && !$0.pattern.isEmpty }.compactMap(JunkFilterCompiledRule.compile)
        lock.lock()
        activeRulesCache = compiled
        convertedRulesCache = nil
        rulesGeneration += 1
        resultCache.removeAllObjects()
        convertedResultCache.removeAllObjects()
        lock.unlock()
    }

    private static func makeResultCache() -> NSCache<NSString, NSString> {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 256
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }

    /// Bộ quy tắc cho chữ đã / chưa chuyển phồn → giản, kèm `rulesGeneration` cùng lúc. Bản đã chuyển dựng một lần dưới
    /// lock (vài quy tắc, ICU + biên dịch regex rẻ); quy tắc không có chữ phồn giữ nguyên bản đã biên dịch, regex lỗi sau
    /// khi chuyển thì bỏ như `updateCache`.
    private nonisolated func activeRules(convertsTraditional: Bool) -> (rules: [JunkFilterCompiledRule], generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard convertsTraditional else { return (activeRulesCache, rulesGeneration) }
        if let converted = convertedRulesCache { return (converted, rulesGeneration) }
        let converted = activeRulesCache.compactMap { entry -> JunkFilterCompiledRule? in
            var rule = entry.rule
            rule.pattern = ChineseTextPipeline.convert(rule.pattern, converts: true)
            rule.replacement = ChineseTextPipeline.convert(rule.replacement, converts: true)
            guard rule.pattern != entry.rule.pattern || rule.replacement != entry.rule.replacement else { return entry }
            return JunkFilterCompiledRule.compile(rule)
        }
        convertedRulesCache = converted
        return (converted, rulesGeneration)
    }

    // MARK: - Filter Execution (Thread-Safe)

    public nonisolated func filterRawContent(_ rawContent: String) -> String {
        filterRawContent(rawContent, convertsTraditional: false)
    }

    /// `convertsTraditional`: `rawContent` đã qua phồn → giản ⇒ lọc bằng bộ quy tắc đã chuyển (1.3.846).
    ///
    /// Chạy trên luồng nền (actor kho chương, Reader dựng đoạn ngoài MainActor, TTS, quét tên riêng AI) — không gọi trên
    /// main. Kết quả y như áp lần lượt **mọi** quy tắc theo thứ tự: quy tắc chỉ bị bỏ khi `JunkFilterTextProbe` chứng minh
    /// nó không thể khớp chữ hiện tại (lượt thay vốn ra 0 chỗ), và cache trả lại kết quả của đúng chuỗi vào + bộ quy tắc.
    public nonisolated func filterRawContent(_ rawContent: String, convertsTraditional: Bool) -> String {
        guard !rawContent.isEmpty else { return rawContent }

        let (active, generation) = activeRules(convertsTraditional: convertsTraditional)

        guard !active.isEmpty else { return rawContent }

        let startTime = CFAbsoluteTimeGetCurrent()
        let cache = convertsTraditional ? convertedResultCache : resultCache
        let key = rawContent as NSString
        let inputLength = key.length
        if let cached = cache.object(forKey: key) {
            logPerf(rules: active.count, detail: "cache=hit", chars: inputLength, since: startTime)
            return cached as String
        }

        // Bridge sang NSString một lần rồi thay tại chỗ, cùng thứ tự và cùng options [] như
        // `stringByReplacingMatches` / `replacingOccurrences` trước đây.
        let buffer = NSMutableString(string: rawContent)
        var probe = JunkFilterTextProbe(text: buffer)
        var ran = 0
        var fired = 0
        for entry in active where probe.mayMatch(entry) {
            ran += 1
            let range = NSRange(location: 0, length: buffer.length)
            let replaced: Int
            if let regex = entry.regex {
                replaced = regex.replaceMatches(in: buffer, options: [], range: range, withTemplate: entry.rule.replacement)
            } else {
                replaced = buffer.replaceOccurrences(of: entry.rule.pattern, with: entry.rule.replacement, options: [], range: range)
            }
            if replaced > 0 {
                fired += 1
                probe.rebuild(from: buffer) // chữ đã đổi ⇒ quy tắc sau xét trên chữ mới
            }
        }
        let result = String(buffer)

        if inputLength <= Self.maxCachedLength {
            lock.lock()
            if generation == rulesGeneration {
                cache.setObject(result as NSString, forKey: key, cost: (inputLength + buffer.length) * 2)
            }
            lock.unlock()
        }
        logPerf(rules: active.count, detail: "ran=\(ran) fired=\(fired)", chars: inputLength, since: startTime)
        return result
    }

    /// `ran` = số quy tắc thật sự chạy thay (phần còn lại bị probe loại), `fired` = số quy tắc thay được ≥ 1 chỗ,
    /// `cache=hit` = trả kết quả đã có của đúng chuỗi vào.
    private nonisolated func logPerf(rules: Int, detail: String, chars: Int, since startTime: CFAbsoluteTime) {
        guard AppLogger.shared.isLoggingEnabled else { return }
        let elapsedMs = String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        AppLogger.shared.log("[ReaderPerf] JunkFilter rules=\(rules) \(detail) chars=\(chars) ms=\(elapsedMs)")
    }

    // MARK: - CRUD Operations

    @MainActor
    public func addRule(pattern: String, replacement: String = "", isRegex: Bool = false) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existingIdx = rules.firstIndex(where: { $0.pattern == trimmed }) {
            rules[existingIdx].isEnabled = true
            rules[existingIdx].replacement = replacement
            rules[existingIdx].isRegex = isRegex
        } else {
            let newRule = JunkFilterRule(pattern: trimmed, replacement: replacement, isRegex: isRegex, isEnabled: true)
            rules.append(newRule)
        }

        saveRules()
    }

    @MainActor
    public func updateRule(_ rule: JunkFilterRule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
            saveRules()
        }
    }

    @MainActor
    public func deleteRule(id: String) {
        rules.removeAll { $0.id == id }
        saveRules()
    }

    @MainActor
    public func moveRules(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
        saveRules()
    }

    @MainActor
    public func clearAllRules() {
        rules.removeAll()
        saveRules()
    }

    // MARK: - Import / Export

    /// Nhập file JSON theo ba `DataImportMode` (popup chọn cách nhập). Trả `nil` khi file không đọc được.
    ///
    /// Khoá so trùng = `pattern` đúng từng chữ (như `addRule` và bản gộp cũ; mẫu rỗng bị bỏ). Luật trùng khoá bị đè
    /// giữ **`id` và vị trí cũ**; luật mới nối cuối — thứ tự danh sách là thứ tự áp dụng nên **không** sắp lại
    /// (bản gộp cũ sắp theo ABC và dựng `Dictionary(uniqueKeysWithValues:)` ⇒ sập khi danh sách sẵn có mẫu trùng).
    @MainActor
    public func importRules(fromJSONString jsonString: String, mode: DataImportMode) -> KeyedImportSummary? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        do {
            let imported = try JSONDecoder().decode([JunkFilterRule].self, from: data).filter { !$0.pattern.isEmpty }
            let merged = KeyedImportMerger.merge(
                existing: rules,
                imported: imported,
                mode: mode,
                key: { $0.pattern },
                isSameContent: { $0.replacement == $1.replacement && $0.isRegex == $1.isRegex && $0.isEnabled == $1.isEnabled },
                overwrite: { existing, incoming in
                    var updated = incoming
                    updated.id = existing.id
                    return updated
                }
            )
            rules = KeyedImportMerger.uniquingIDs(merged.elements, id: \JunkFilterRule.id, makeID: { UUID().uuidString })
            saveRules()
            return merged.summary
        } catch {
            AppLogger.shared.log("❌ [JunkFilterManager] Lỗi import JSON: \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    public func exportRulesToJSON() -> String? {
        guard let data = try? JSONEncoder().encode(rules),
              let jsonStr = String(data: data, encoding: .utf8) else { return nil }
        return jsonStr
    }
}
