import Foundation

public struct TTSReplacementRule: Codable, Identifiable, Equatable {
    public var id: UUID
    public var pattern: String
    public var replacement: String
    public var isEnabled: Bool
    
    public init(id: UUID = UUID(), pattern: String, replacement: String, isEnabled: Bool = true) {
        self.id = id
        self.pattern = pattern
        self.replacement = replacement
        self.isEnabled = isEnabled
    }
}

public final class TTSReplacementManager: ObservableObject {
    public static let shared = TTSReplacementManager()
    
    @Published public var rules: [TTSReplacementRule] = []
    
    private let fileManager = FileManager.default
    
    private var fileURL: URL? {
        guard let appSupport = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        let rootURL = appSupport.appendingPathComponent("FreeBook/TTS", isDirectory: true)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL.appendingPathComponent("character_replacements.json")
    }
    
    private init() {
        loadRules()
    }
    
    public func loadRules() {
        guard let url = fileURL else { return }
        if fileManager.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode([TTSReplacementRule].self, from: data)
                self.rules = decoded
            } catch {
                AppLogger.shared.log("❌ Lỗi load character_replacements.json: \(error.localizedDescription)")
                loadDefaultRules()
            }
        } else {
            loadDefaultRules()
        }
    }
    
    private func loadDefaultRules() {
        self.rules = [
            TTSReplacementRule(pattern: "\"", replacement: ""),
            TTSReplacementRule(pattern: "(", replacement: ""),
            TTSReplacementRule(pattern: ")", replacement: ""),
            TTSReplacementRule(pattern: "...", replacement: "…")
        ]
        saveRules()
    }
    
    public func saveRules() {
        guard let url = fileURL else { return }
        do {
            let data = try JSONEncoder().encode(rules)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.log("❌ Lỗi lưu character_replacements.json: \(error.localizedDescription)")
        }
    }
    
    public func addRule(_ rule: TTSReplacementRule) {
        rules.append(rule)
        saveRules()
    }
    
    public func updateRule(_ rule: TTSReplacementRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
            saveRules()
        }
    }
    
    public func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
        saveRules()
    }
    
    public func moveRules(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
        saveRules()
    }
    
    public func applyReplacements(to text: String) -> String {
        var result = text
        for rule in rules where rule.isEnabled {
            if !rule.pattern.isEmpty {
                result = result.replacingOccurrences(of: rule.pattern, with: rule.replacement)
            }
        }
        return result
    }
    
    public func exportRulesToJSON() -> String? {
        do {
            let data = try JSONEncoder().encode(rules)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    public func importRules(fromJSONString jsonString: String, mode: ImportMode) -> Bool {
        guard let data = jsonString.data(using: .utf8) else { return false }
        do {
            let imported = try JSONDecoder().decode([TTSReplacementRule].self, from: data)
            
            var validatedRules: [TTSReplacementRule] = []
            for var rule in imported {
                if rule.id.uuidString.isEmpty {
                    rule.id = UUID()
                }
                validatedRules.append(rule)
            }
            
            switch mode {
            case .overwrite:
                self.rules = validatedRules
            case .merge:
                for rule in validatedRules {
                    if !self.rules.contains(where: { $0.pattern == rule.pattern }) {
                        self.rules.append(rule)
                    }
                }
            }
            saveRules()
            return true
        } catch {
            AppLogger.shared.log("❌ Lỗi import cấu hình thay thế ký tự: \(error.localizedDescription)")
            return false
        }
    }
    
    public enum ImportMode {
        case overwrite
        case merge
    }
}
