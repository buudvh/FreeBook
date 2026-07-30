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

@MainActor
public final class JunkFilterManager: ObservableObject {
    public static let shared = JunkFilterManager()

    @Published public private(set) var rules: [JunkFilterRule] = []
    private let lock = NSLock()
    private var activeRulesCache: [JunkFilterRule] = []

    private var rulesFileURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let directory = paths[0].appendingPathComponent("translate", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        return directory.appendingPathComponent("junk_filter_rules.json")
    }

    private init() {
        loadRules()
    }

    // MARK: - Persistence

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
        let enabledOnly = list.filter { $0.isEnabled && !$0.pattern.isEmpty }
        lock.lock()
        activeRulesCache = enabledOnly
        lock.unlock()
    }

    // MARK: - Filter Execution (Thread-Safe)

    public nonisolated func filterRawContent(_ rawContent: String) -> String {
        guard !rawContent.isEmpty else { return rawContent }

        lock.lock()
        let active = activeRulesCache
        lock.unlock()

        guard !active.isEmpty else { return rawContent }

        var result = rawContent

        for rule in active {
            if rule.isRegex {
                if let regex = try? NSRegularExpression(pattern: rule.pattern, options: []) {
                    let range = NSRange(location: 0, length: result.utf16.count)
                    result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: rule.replacement)
                }
            } else {
                result = result.replacingOccurrences(of: rule.pattern, with: rule.replacement)
            }
        }

        return result
    }

    // MARK: - CRUD Operations

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

    public func updateRule(_ rule: JunkFilterRule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
            saveRules()
        }
    }

    public func deleteRule(id: String) {
        rules.removeAll { $0.id == id }
        saveRules()
    }

    public func toggleRule(id: String, isEnabled: Bool) {
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].isEnabled = isEnabled
            saveRules()
        }
    }

    public func moveRules(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
        saveRules()
    }

    public func clearAllRules() {
        rules.removeAll()
        saveRules()
    }

    // MARK: - Import / Export

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

    public func exportRulesToJSON() -> String? {
        guard let data = try? JSONEncoder().encode(rules),
              let jsonStr = String(data: data, encoding: .utf8) else { return nil }
        return jsonStr
    }
}
