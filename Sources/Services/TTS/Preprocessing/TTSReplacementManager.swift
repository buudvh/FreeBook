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

    public enum AddRuleResult: Equatable {
        case added
        case replaced
    }
    
    /// Mọi đường thay đổi rule (thêm/sửa/xoá/di chuyển/nạp lại/reset/import, kể cả gán trực tiếp từ
    /// ngoài class) đều đi qua setter này, nên `didSet` là chỗ duy nhất cần dựng lại kế hoạch thay thế.
    @Published public var rules: [TTSReplacementRule] = [] {
        didSet { rebuildReplacementPlan() }
    }

    /// Một bước trong kế hoạch thay thế đã biên dịch. Thứ tự các bước **giữ nguyên** thứ tự rule trong
    /// `rules`, nên hành vi phụ thuộc thứ tự (rule sau tác động lên kết quả rule trước) không đổi.
    private enum ReplacementStep {
        /// Gộp một dãy rule liền nhau có pattern dài đúng 1 ký tự thành **một lượt quét** duy nhất.
        case characterMap([Character: String])
        /// Giữ nguyên đường cũ `replacingOccurrences`: pattern nhiều ký tự, hoặc dãy 1 ký tự có nối tầng.
        case scan([TTSReplacementRule])
    }

    /// Kế hoạch đã biên dịch. `applyReplacements` chạy trên thread nền (tổng hợp TTS, `scheduleNghiRefill`)
    /// nên đọc/ghi phải qua lock — cùng mô hình với `JunkFilterManager.activeRulesCache`.
    private let planLock = NSLock()
    private nonisolated(unsafe) var replacementPlan: [ReplacementStep] = []
    
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
        // `loadRules()` có thể thoát sớm khi không lấy được thư mục Application Support; lúc đó `rules`
        // không được gán nên `didSet` không chạy. Dựng tường minh một lần ở đây cho chắc.
        rebuildReplacementPlan()
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
            // Gộp vào mảng cục bộ rồi gán một lần: tránh dựng lại kế hoạch (và bắn `objectWillChange`)
            // cho từng rule mặc định.
            var merged = self.rules
            for rule in Self.defaultRulesList {
                if !merged.contains(where: { $0.pattern == rule.pattern }) {
                    merged.append(rule)
                }
            }
            self.rules = merged
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
    
    @discardableResult
    public func addRule(_ rule: TTSReplacementRule) -> AddRuleResult {
        var updatedRules = rules
        let previousCount = updatedRules.count
        updatedRules.removeAll { $0.pattern == rule.pattern }
        let replacedExistingRule = updatedRules.count != previousCount
        updatedRules.append(rule)
        rules = updatedRules
        saveRules()
        return replacedExistingRule ? .replaced : .added
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
    
    /// Áp dụng luật thay thế lên một đoạn. Đây là đường nóng: gọi cho **từng đoạn** khi tổng hợp và trong
    /// `scheduleNghiRefill`. Trước đây mỗi rule là một lượt `replacingOccurrences` riêng (~130 lượt quét
    /// toàn văn bản + 130 chuỗi mới mỗi đoạn); giờ chạy theo kế hoạch đã biên dịch sẵn.
    public func applyReplacements(to text: String) -> String {
        guard !text.isEmpty else { return text }
        planLock.lock()
        let plan = replacementPlan
        planLock.unlock()
        guard !plan.isEmpty else { return text }
        var result = text
        for step in plan {
            switch step {
            case .characterMap(let map):
                result = Self.applyCharacterMap(map, to: result)
            case .scan(let group):
                for rule in group {
                    result = result.replacingOccurrences(of: rule.pattern, with: rule.replacement)
                }
            }
        }
        return result
    }

    /// Biên dịch `rules` thành số lượt quét tối thiểu. Rule 1 ký tự **liền nhau** gộp thành một bảng tra
    /// `[Character: String]`; rule nhiều ký tự giữ nguyên `replacingOccurrences` theo đúng thứ tự cũ, nên
    /// hành vi nối tầng vẫn y nguyên (ví dụ `...` chạy trước `....` nên `....` vẫn ra `…` rồi `.`).
    private func rebuildReplacementPlan() {
        var steps: [ReplacementStep] = []
        var pendingCharacters: [TTSReplacementRule] = []
        var pendingScans: [TTSReplacementRule] = []
        func flushCharacters() {
            guard !pendingCharacters.isEmpty else { return }
            steps.append(Self.compileCharacterRun(pendingCharacters))
            pendingCharacters.removeAll(keepingCapacity: true)
        }
        func flushScans() {
            guard !pendingScans.isEmpty else { return }
            steps.append(.scan(pendingScans))
            pendingScans.removeAll(keepingCapacity: true)
        }
        for rule in rules where rule.isEnabled && !rule.pattern.isEmpty {
            if rule.pattern.count == 1 {
                flushScans()
                pendingCharacters.append(rule)
            } else {
                flushCharacters()
                pendingScans.append(rule)
            }
        }
        flushCharacters()
        flushScans()
        planLock.lock()
        replacementPlan = steps
        planLock.unlock()
    }

    /// Dựng bảng tra cho một dãy rule 1 ký tự. Trùng `pattern` thì rule **đầu tiên** thắng, giống đường cũ
    /// (rule sau quét lại thì ký tự đó đã bị thay xong nên không còn gì để khớp). Nếu dãy có **nối tầng** —
    /// chuỗi thay thế của một rule chứa lại pattern của rule khác trong dãy — thì không gộp được, vì một
    /// lượt quét không xử lý lại phần vừa sinh ra; lúc đó giữ nguyên đường cũ cho cả dãy.
    private static func compileCharacterRun(_ run: [TTSReplacementRule]) -> ReplacementStep {
        var map: [Character: String] = [:]
        map.reserveCapacity(run.count)
        var patterns: Set<Character> = []
        for rule in run {
            guard let character = rule.pattern.first else { continue }
            patterns.insert(character)
            if map[character] == nil {
                map[character] = rule.replacement
            }
        }
        let hasCascade = run.contains { rule in
            rule.replacement.contains { patterns.contains($0) }
        }
        guard !hasCascade else { return .scan(run) }
        return .characterMap(map)
    }

    /// Một lượt quét duy nhất: ký tự nào có trong bảng thì nối chuỗi thay thế, còn lại giữ nguyên.
    private static func applyCharacterMap(_ map: [Character: String], to text: String) -> String {
        guard !map.isEmpty else { return text }
        var buffer = ""
        buffer.reserveCapacity(text.utf8.count + text.utf8.count / 4)
        for character in text {
            if let replacement = map[character] {
                buffer.append(replacement)
            } else {
                buffer.append(character)
            }
        }
        return buffer
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
                // Gộp cục bộ rồi gán một lần, xem chú thích ở `resetToDefaults`.
                var merged = self.rules
                for rule in validatedRules {
                    if !merged.contains(where: { $0.pattern == rule.pattern }) {
                        merged.append(rule)
                    }
                }
                self.rules = merged
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
