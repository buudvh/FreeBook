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

public enum JunkFilterImportMode {
    case merge
    case overwrite
}

public final class JunkFilterManager: ObservableObject {
    public static let shared = JunkFilterManager()

    @MainActor @Published public private(set) var rules: [JunkFilterRule] = []
    private let lock = NSLock()
    /// Quy tắc đang bật kèm regex đã biên dịch sẵn (nil với quy tắc literal).
    private nonisolated(unsafe) var activeRulesCache: [(rule: JunkFilterRule, regex: NSRegularExpression?)] = []

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
        // Biên dịch regex một lần khi danh sách quy tắc đổi; regex lỗi bị bỏ qua như `try?` cũ.
        let compiled = list.filter { $0.isEnabled && !$0.pattern.isEmpty }
            .compactMap { rule -> (rule: JunkFilterRule, regex: NSRegularExpression?)? in
                guard rule.isRegex else { return (rule, nil) }
                guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: []) else { return nil }
                return (rule, regex)
            }
        lock.lock()
        activeRulesCache = compiled
        lock.unlock()
    }

    // MARK: - Filter Execution (Thread-Safe)

    public nonisolated func filterRawContent(_ rawContent: String) -> String {
        guard !rawContent.isEmpty else { return rawContent }

        lock.lock()
        let active = activeRulesCache
        lock.unlock()

        guard !active.isEmpty else { return rawContent }

        let startTime = CFAbsoluteTimeGetCurrent()
        // Bridge sang NSString một lần rồi thay tại chỗ, cùng thứ tự và cùng options [] như
        // `stringByReplacingMatches` / `replacingOccurrences` trước đây.
        let buffer = NSMutableString(string: rawContent)
        for entry in active {
            let range = NSRange(location: 0, length: buffer.length)
            if let regex = entry.regex {
                regex.replaceMatches(in: buffer, options: [], range: range, withTemplate: entry.rule.replacement)
            } else {
                buffer.replaceOccurrences(of: entry.rule.pattern, with: entry.rule.replacement, options: [], range: range)
            }
        }
        let result = String(buffer)

        if AppLogger.shared.isLoggingEnabled {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            AppLogger.shared.log(String(
                format: "[ReaderPerf] JunkFilter rules=%d chars=%d ms=%.2f",
                active.count, rawContent.utf16.count, elapsedMs
            ))
        }
        return result
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

    @MainActor
    public func importRules(fromJSONString jsonString: String, mode: JunkFilterImportMode) -> Bool {
        guard let data = jsonString.data(using: .utf8) else { return false }
        do {
            let imported = try JSONDecoder().decode([JunkFilterRule].self, from: data)
            switch mode {
            case .merge:
                var currentMap = Dictionary(uniqueKeysWithValues: rules.map { ($0.pattern, $0) })
                for rule in imported {
                    if !rule.pattern.isEmpty {
                        currentMap[rule.pattern] = rule
                    }
                }
                rules = Array(currentMap.values).sorted { $0.pattern.localizedCompare($1.pattern) == .orderedAscending }
            case .overwrite:
                rules = imported.filter { !$0.pattern.isEmpty }
            }
            saveRules()
            return true
        } catch {
            AppLogger.shared.log("❌ [JunkFilterManager] Lỗi import JSON: \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    public func exportRulesToJSON() -> String? {
        guard let data = try? JSONEncoder().encode(rules),
              let jsonStr = String(data: data, encoding: .utf8) else { return nil }
        return jsonStr
    }
}
