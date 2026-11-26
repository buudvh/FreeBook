import Foundation

/// `DICT_TOKEN_WITHOUT_DICTIONARY` cho token tùy chọn `<@tên>` (1.3.1063), tính **theo từng tên** token: parser cố ý không
/// tra token lúc dịch rule (`QuickTranslationRuleParser+CustomToken`), nên token chưa tạo, đang tắt hay chưa có từ chỉ lộ ra
/// ở đây — lỗi trạng thái lúc chạy như từ điển chưa nạp. `dictionaryIssues()` nối kết quả này vào cuối.
extension QuickTranslationRuleStore {
    private static let maxCustomTokenIssues = 400

    func customTokenIssues(
        in snapshot: QuickTranslationRuleSnapshot,
        configuration: QuickTranslationRuleTokenSettings.Configuration
    ) -> [QuickTranslationRuleIssue] {
        let tokenStore = QuickTranslationCustomTokenStore.shared
        var states: [String: QuickTranslationCustomTokenStore.Availability] = [:]
        var issues: [QuickTranslationRuleIssue] = []

        for rule in snapshot.rules where rule.requiredDictionaryKinds.contains(.custom) {
            guard rule.isEnabled(for: configuration) else { continue }
            // Rule đang tắt ở file tắt chung thì cảnh báo chỉ là tiếng ồn (cùng luật với phần từ điển).
            guard !QuickTranslationRuleDisableStore.shared.isDisabled(pattern: rule.pattern, in: .global) else { continue }

            let problems = Self.customTokenNames(in: rule.elements).compactMap { name -> String? in
                let state = states[name] ?? tokenStore.availability(of: name)
                states[name] = state
                switch state {
                case .usable: return nil
                case .missing: return "<@\(name)> chưa có"
                case .disabled: return "<@\(name)> đang tắt"
                case .empty: return "<@\(name)> chưa có từ nào"
                }
            }
            guard !problems.isEmpty else { continue }

            issues.append(QuickTranslationRuleIssue(
                sourceLine: rule.sourceLine,
                code: .dictTokenWithoutDictionary,
                message: "Token tùy chọn \(problems.joined(separator: ", ")) ⇒ chỗ dùng token đó không khớp",
                rawLine: "\(rule.pattern) = \(rule.replacement)"
            ))
            if issues.count >= Self.maxCustomTokenIssues { break }
        }
        return issues
    }

    /// Tên các `<@tên>` trong mẫu (kể cả trong nhóm), không trùng, theo thứ tự xuất hiện.
    static func customTokenNames(in elements: [QuickTranslationRuleElement]) -> [String] {
        var names: [String] = []
        func collect(_ elements: [QuickTranslationRuleElement]) {
            for element in elements {
                if case .group(let alternatives) = element.kind {
                    alternatives.forEach(collect)
                } else if let name = element.customTokenName, !names.contains(name) {
                    names.append(name)
                }
            }
        }
        collect(elements)
        return names
    }
}
