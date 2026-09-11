import Foundation

/// UI mutations execute serially off-main; existing stores retain file ownership and semantics.
actor QuickTranslationRuleMutation {
    static let shared = QuickTranslationRuleMutation()

    enum Command: Sendable {
        case upsert(oldPattern: String?, pattern: String, replacement: String, scope: QuickTranslationRuleScope)
        case delete(pattern: String, scope: QuickTranslationRuleScope)
        case disable(pattern: String, disabled: Bool, scope: QuickTranslationRuleScope)
        case move(pattern: String, replacement: String, from: QuickTranslationRuleScope, to: QuickTranslationRuleScope)
    }

    func perform(_ command: Command) -> QuickTranslationRuleStore.LoadOutcome {
        switch command {
        case .upsert(let oldPattern, let pattern, let replacement, let scope):
            guard let oldPattern else {
                return QuickTranslationRuleTransfer.copy(pattern: pattern, replacement: replacement, to: scope)
            }
            switch scope {
            case .global:
                return QuickTranslationRuleStore.shared.updateRule(
                    oldPattern: oldPattern, newPattern: pattern, replacement: replacement)
            case .book(let bookId):
                return QuickTranslationRuleBookStore.shared.updateRule(
                    oldPattern: oldPattern, newPattern: pattern, replacement: replacement, bookId: bookId)
            }
        case .delete(let pattern, let scope):
            return delete(pattern, from: scope)
        case .disable(let pattern, let disabled, let scope):
            switch QuickTranslationRuleDisableStore.shared.setDisabled(disabled, pattern: pattern, scope: scope) {
            case .success: return .success(ruleCount: 0, warningCount: 0)
            case .failure(let message): return .failure(message: message)
            }
        case .move(let pattern, let replacement, let source, let destination):
            let copy = QuickTranslationRuleTransfer.copy(pattern: pattern, replacement: replacement, to: destination)
            guard case .success = copy else { return copy }
            let removal = delete(pattern, from: source)
            guard case .success = removal else {
                return .failure(message: "Đã ghi ở đích nhưng chưa xoá được ở nguồn; rule đang ở cả hai phạm vi.")
            }
            return removal
        }
    }

    private func delete(_ pattern: String, from scope: QuickTranslationRuleScope) -> QuickTranslationRuleStore.LoadOutcome {
        switch scope {
        case .global: return QuickTranslationRuleStore.shared.deleteRule(pattern: pattern)
        case .book(let bookId): return QuickTranslationRuleBookStore.shared.deleteRule(pattern: pattern, bookId: bookId)
        }
    }
}
