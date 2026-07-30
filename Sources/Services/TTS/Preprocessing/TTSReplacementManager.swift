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
    
    public static let defaultRulesList: [TTSReplacementRule] = [
        // Ký hiệu & Toán học phát âm tiếng Việt
        TTSReplacementRule(pattern: "+", replacement: " cộng "),
        TTSReplacementRule(pattern: "@", replacement: " a còng "),
        TTSReplacementRule(pattern: "%", replacement: " phần trăm "),
        TTSReplacementRule(pattern: "=", replacement: " "),
        TTSReplacementRule(pattern: "&", replacement: " "),
        TTSReplacementRule(pattern: "×", replacement: " nhân "),
        TTSReplacementRule(pattern: "÷", replacement: " chia "),
        TTSReplacementRule(pattern: "±", replacement: " cộng trừ "),
        TTSReplacementRule(pattern: "≠", replacement: " khác "),
        TTSReplacementRule(pattern: "≈", replacement: " xấp xỉ "),
        TTSReplacementRule(pattern: "€", replacement: " ơ-rô "),
        TTSReplacementRule(pattern: "¥", replacement: " yên "),
        TTSReplacementRule(pattern: "£", replacement: " bảng "),
        
        // Dấu chấm giữa phân cách tên riêng Trung/Tây/Nhật (Harry·Potter, Khắc·Lỗ·Đồ)
        TTSReplacementRule(pattern: "·", replacement: " "),
        TTSReplacementRule(pattern: "•", replacement: " "),
        TTSReplacementRule(pattern: "‧", replacement: " "),
        TTSReplacementRule(pattern: "ㆍ", replacement: " "),
        TTSReplacementRule(pattern: "⋅", replacement: " "),
        TTSReplacementRule(pattern: "･", replacement: " "),
        
        // Ngoặc kép & Ngoặc đơn trích dẫn / Lời thoại (thay bằng dấu phẩy " " để ngắt nhịp & nhấn mạnh)
        TTSReplacementRule(pattern: "\"", replacement: " "),
        TTSReplacementRule(pattern: "'", replacement: " "),
        TTSReplacementRule(pattern: "“", replacement: " "),
        TTSReplacementRule(pattern: "”", replacement: " "),
        TTSReplacementRule(pattern: "‘", replacement: " "),
        TTSReplacementRule(pattern: "’", replacement: " "),
        TTSReplacementRule(pattern: "„", replacement: " "),
        TTSReplacementRule(pattern: "‟", replacement: " "),
        TTSReplacementRule(pattern: "«", replacement: " "),
        TTSReplacementRule(pattern: "»", replacement: " "),
        TTSReplacementRule(pattern: "‹", replacement: " "),
        TTSReplacementRule(pattern: "›", replacement: " "),
        TTSReplacementRule(pattern: "＂", replacement: " "),
        TTSReplacementRule(pattern: "＇", replacement: " "),
        TTSReplacementRule(pattern: "❝", replacement: " "),
        TTSReplacementRule(pattern: "❞", replacement: " "),
        TTSReplacementRule(pattern: "❛", replacement: " "),
        TTSReplacementRule(pattern: "❜", replacement: " "),
        TTSReplacementRule(pattern: "〞", replacement: " "),
        TTSReplacementRule(pattern: "〟", replacement: " "),
        
        // Dấu ngoặc chú thích / phụ đề / Hán Nhật (thay bằng dấu phẩy " " để ngắt nhịp & nhấn mạnh)
        TTSReplacementRule(pattern: "(", replacement: " "),
        TTSReplacementRule(pattern: ")", replacement: " "),
        TTSReplacementRule(pattern: "[", replacement: " "),
        TTSReplacementRule(pattern: "]", replacement: " "),
        TTSReplacementRule(pattern: "{", replacement: " "),
        TTSReplacementRule(pattern: "}", replacement: " "),
        TTSReplacementRule(pattern: "（", replacement: " "),
        TTSReplacementRule(pattern: "）", replacement: " "),
        TTSReplacementRule(pattern: "［", replacement: " "),
        TTSReplacementRule(pattern: "］", replacement: " "),
        TTSReplacementRule(pattern: "｛", replacement: " "),
        TTSReplacementRule(pattern: "｝", replacement: " "),
        
        // Ngoặc trang trí Hán / Nhật
        TTSReplacementRule(pattern: "【", replacement: " "),
        TTSReplacementRule(pattern: "】", replacement: " "),
        TTSReplacementRule(pattern: "〔", replacement: " "),
        TTSReplacementRule(pattern: "〕", replacement: " "),
        TTSReplacementRule(pattern: "〖", replacement: " "),
        TTSReplacementRule(pattern: "〗", replacement: " "),
        TTSReplacementRule(pattern: "「", replacement: " "),
        TTSReplacementRule(pattern: "」", replacement: " "),
        TTSReplacementRule(pattern: "『", replacement: " "),
        TTSReplacementRule(pattern: "』", replacement: " "),
        TTSReplacementRule(pattern: "《", replacement: " "),
        TTSReplacementRule(pattern: "》", replacement: " "),
        
        // Dấu chấm ngắt nhịp & Phân cách
        TTSReplacementRule(pattern: "...", replacement: "…"),
        TTSReplacementRule(pattern: "....", replacement: "…"),
        TTSReplacementRule(pattern: "--", replacement: " "),
        TTSReplacementRule(pattern: "---", replacement: " "),
        TTSReplacementRule(pattern: "—", replacement: " "),
        
        // Biểu tượng rác, Nốt nhạc, Trái tim & Khối hình học trang trí
        TTSReplacementRule(pattern: "*", replacement: " "),
        TTSReplacementRule(pattern: "#", replacement: " "),
        TTSReplacementRule(pattern: "~", replacement: " "),
        TTSReplacementRule(pattern: "^", replacement: " "),
        TTSReplacementRule(pattern: "\\", replacement: " "),
        TTSReplacementRule(pattern: "|", replacement: " "),
        TTSReplacementRule(pattern: "♪", replacement: " "),
        TTSReplacementRule(pattern: "♫", replacement: " "),
        TTSReplacementRule(pattern: "♥", replacement: " "),
        TTSReplacementRule(pattern: "♡", replacement: " "),
        TTSReplacementRule(pattern: "❤", replacement: " "),
        TTSReplacementRule(pattern: "❥", replacement: " "),
        TTSReplacementRule(pattern: "◆", replacement: " "),
        TTSReplacementRule(pattern: "◇", replacement: " "),
        TTSReplacementRule(pattern: "■", replacement: " "),
        TTSReplacementRule(pattern: "□", replacement: " "),
        TTSReplacementRule(pattern: "▲", replacement: " "),
        TTSReplacementRule(pattern: "△", replacement: " "),
        TTSReplacementRule(pattern: "▼", replacement: " "),
        TTSReplacementRule(pattern: "▽", replacement: " "),
        TTSReplacementRule(pattern: "○", replacement: " "),
        TTSReplacementRule(pattern: "●", replacement: " "),
        TTSReplacementRule(pattern: "◎", replacement: " "),
        TTSReplacementRule(pattern: "☆", replacement: " "),
        TTSReplacementRule(pattern: "★", replacement: " "),
        TTSReplacementRule(pattern: "✦", replacement: " "),
        TTSReplacementRule(pattern: "✧", replacement: " ")
    ]
    
    private func loadDefaultRules() {
        self.rules = Self.defaultRulesList
        saveRules()
    }
    
    public func resetToDefaults(mode: ImportMode) {
        switch mode {
        case .overwrite:
            self.rules = Self.defaultRulesList
        case .merge:
            for rule in Self.defaultRulesList {
                if !self.rules.contains(where: { $0.pattern == rule.pattern }) {
                    self.rules.append(rule)
                }
            }
        }
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
