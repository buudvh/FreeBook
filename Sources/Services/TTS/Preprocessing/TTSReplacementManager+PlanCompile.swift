import Foundation

/// Phần **biên dịch kế hoạch** của `TTSReplacementManager`.
///
/// Tách khỏi file chính vì `TTSReplacementManager.swift` ở **391/400** dòng, mà lượt này phải thêm cả tầng
/// rule riêng theo truyện. Đây là extension **cùng file type** nên vẫn dùng được `ReplacementStep` (đã hạ
/// `private` → `internal` ở file chính) — Swift giới hạn `private` theo file, không theo type.
extension TTSReplacementManager {

    /// Biên dịch `rules` thành số lượt quét tối thiểu. Rule 1 ký tự **liền nhau** gộp thành một bảng tra
    /// `[Character: String]`; rule nhiều ký tự giữ nguyên `replacingOccurrences` theo đúng thứ tự cũ, nên
    /// hành vi nối tầng vẫn y nguyên (ví dụ `...` chạy trước `....` nên `....` vẫn ra `…` rồi `.`).
    ///
    /// Là `static` để tầng rule riêng theo truyện (`TTSReplacementManager+BookScope.swift`) dùng **cùng một**
    /// thuật toán — hai bản biên dịch song song là hai hành vi chờ ngày lệch nhau.
    static func compile(_ rules: [TTSReplacementRule]) -> [ReplacementStep] {
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
        return steps
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
}
