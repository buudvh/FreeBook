import SwiftUI

/// Chip rule và thao tác rule của `ComicDefinitionSheet` — chép từ `ReaderView+RuleTools` / `ReaderView+DefinitionLoading`.
/// Câu gốc là một bong bóng (không phải tên chương) ⇒ không soi bộ rule tên chương.
extension ComicDefinitionSheet {

    /// Chẩn đoán rule của **cả câu** off-main (debounce 150 ms, lượt mới huỷ lượt cũ); giữ chip đang chọn nếu còn.
    func refreshDefinitionRules() {
        guard !sentence.isEmpty else { return }
        definitionSession.ruleTask?.cancel()
        let sessionID = definitionSession.identity
        let text = sentence
        let book = bookId
        let worker = definitionSession.worker
        definitionSession.loadingRules = true
        definitionSession.ruleTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                let result = try await CancellableTranslationWork.run {
                    try await worker.traces(sentence: text, bookId: book, selection: NSRange(location: 0, length: 0))
                }
                guard definitionSession.identity == sessionID else { return }
                guard result.generation == TranslateUtils.translationGenerationToken(for: book) else {
                    refreshDefinitionRules()
                    return
                }
                withTransaction(Transaction(animation: nil)) {
                    ruleTraces = result.values
                    definitionSession.loadingRules = false
                    if let focusedRuleTraceID, !ruleTraces.contains(where: { $0.id == focusedRuleTraceID }) {
                        self.focusedRuleTraceID = nil
                    }
                }
            } catch is CancellationError {
            } catch {
                if definitionSession.identity == sessionID { definitionSession.loadingRules = false }
            }
        }
    }

    func handleRuleAction(_ trace: QuickTranslationRuleTrace, _ action: ReaderRuleAction) {
        switch action {
        case .setDisabled(let disabled, let scope):
            // File tắt riêng tác động mọi bộ nhưng chỉ cho truyện này; file tắt chung / tên chương chỉ tác động bộ đó.
            let target = scope.bookId == nil ? "ở \(scope.longLabel.lowercased()) cho mọi truyện" : "cho truyện này"
            performRuleCommand(.disable(pattern: trace.pattern, disabled: disabled, scope: scope),
                message: "\(disabled ? "Đã tắt" : "Đã bật") rule \(target).")
        case .edit:
            ruleEditorMode = .edit(
                pattern: trace.pattern,
                replacement: trace.replacement,
                sourceLine: trace.sourceLine,
                scope: trace.scope
            )
        case .delete:
            performRuleCommand(.delete(pattern: trace.pattern, scope: trace.scope),
                message: "Đã xoá rule khỏi \(trace.scope.longLabel.lowercased()).")
        case .moveScope(let destination):
            // Ghi ở đích rồi xoá ở nguồn (`QuickTranslationRuleMutation.move`), như Reader.
            performRuleCommand(.move(pattern: trace.pattern, replacement: trace.replacement,
                from: trace.scope, to: destination), message: "Đã chuyển rule sang \(destination.longLabel.lowercased()).")
        }
    }

    /// Lưu rule mới (nút `+`) hoặc rule sửa từ chip; trả `LoadOutcome` để sheet sửa rule biết đóng hay giữ lại kèm lý do.
    func saveRuleFromEditor(
        pattern: String,
        replacement: String,
        scope: QuickTranslationRuleScope,
        replacing: String?
    ) async -> QuickTranslationRuleStore.LoadOutcome {
        let session = definitionSession.identity
        let outcome = await QuickTranslationRuleMutation.shared.perform(
            .upsert(oldPattern: replacing, pattern: pattern, replacement: replacement, scope: scope))
        if definitionSession.identity == session {
            handleRuleOutcome(outcome, successMessage: "Đã lưu rule vào \(scope.longLabel.lowercased()).")
        }
        return outcome
    }

    func defaultRuleEditorScope(for mode: QuickTranslationRuleEditorSheet.Mode) -> QuickTranslationRuleScope {
        if case .edit(_, _, _, let scope) = mode { return scope }
        return .book(bookId)
    }

    private func performRuleCommand(_ command: QuickTranslationRuleMutation.Command, message: String) {
        let session = definitionSession.identity
        Task { @MainActor in
            let result = await QuickTranslationRuleMutation.shared.perform(command)
            guard definitionSession.identity == session else { return }
            handleRuleOutcome(result, successMessage: message)
        }
    }

    private func handleRuleOutcome(_ outcome: QuickTranslationRuleStore.LoadOutcome, successMessage: String) {
        switch outcome {
        case .success:
            refreshDefinitionRules()
            // Cụm đang chọn có thể đổi nghĩa theo rule vừa sửa — tra lại, giữ chữ người dùng đang gõ.
            loadDefinitionData(preservingMeaning: true)
            ToastManager.shared.show(message: successMessage, type: .success)
        case .rejected(let issues):
            let detail = issues.first.map { "dòng \($0.sourceLine) — \($0.code.rawValue)" } ?? "\(issues.count) dòng"
            ToastManager.shared.show(message: "Bộ rule có lỗi nặng (\(detail)); không đổi gì.", type: .error)
        case .failure(let message):
            ToastManager.shared.show(message: message, type: .error)
        }
    }
}
