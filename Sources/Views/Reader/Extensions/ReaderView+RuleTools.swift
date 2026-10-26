import SwiftUI

/// Hai công cụ mới của menu bôi đen: **Copy nội dung gốc** và **Check rule**.
///
/// Đặt ở file riêng vì `ReaderView.swift` đã vượt baseline dòng của `check_architecture.py` nên chỉ
/// được giảm; ở đó chỉ còn phần khai `@State`. Sheet của các panel nằm ở `ReaderView+SelectionSheets`.
///
/// Bất biến của cả hai công cụ: chúng dùng **chung** `originalSentence` + `selectedWordOffset/Length`
/// với màn Dịch và panel Xoá từ rác, nên mở một cái phải đóng những cái còn lại.
extension ReaderView {

    // MARK: - Copy nội dung gốc

    func openCopyOriginalPanel() {
        closeOtherSelectionPanels(except: .copyOriginal)
        showingCopyOriginalSheet = true
        updateEditorFromSelection()
    }

    /// Copy cụm gốc đang chọn. **Chỉ** gọi từ `onDismiss` của sheet copy gốc
    /// (`ReaderView+SelectionSheets`): nút Copy, kéo xuống và chạm vùng mờ đều chỉ đóng sheet,
    /// rồi `onDismiss` copy đúng một lần. Gọi thêm ở chỗ khác là copy hai lần (hai toast).
    func commitCopyOriginal() {
        let ns = originalSentence as NSString
        let range = NSRange(location: selectedWordOffset, length: selectedWordLength)

        guard selectedWordOffset >= 0, selectedWordLength > 0, NSMaxRange(range) <= ns.length else { return }
        let text = ns.substring(with: range)
        guard !text.isEmpty else { return }

        UIPasteboard.general.string = text
        ToastManager.shared.show(message: "Đã copy gốc: \"\(Self.shortened(text))\"")
    }

    /// Toast không được dài bằng cả đoạn văn.
    static func shortened(_ text: String, limit: Int = 40) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    // MARK: - Check rule

    /// Mở panel Dịch — nay là chỗ duy nhất có Check rule (1.3.334). Panel mở **ngay**, dải chip rule
    /// điền vào sau: từ 1.3.339 việc chẩn đoán chạy off-main và có debounce (xem `refreshRuleTraces`),
    /// nên không còn chặn cú bấm mở panel.
    func openDefinitionPanel() {
        definitionSession.begin()
        closeOtherSelectionPanels(except: nil)
        didChangeRuleData = false
        focusedRuleTraceID = nil
        ruleTraces = []
        showingDefinitionSheet = true
        viewModel?.setTranslationRefreshDeferred(true)
        updateEditorFromSelection()
        refreshRuleTraces()
    }

    /// Chẩn đoán lại **cả đoạn** rồi giữ lại focus nếu chip cũ còn tồn tại.
    ///
    /// Ba điểm của bản 1.3.339, đều vì hàm này được gọi lại sau **mỗi** hành động rule (bật/tắt, sửa,
    /// xoá, chuyển phạm vi):
    ///
    /// 1. **Debounce 150 ms** — bấm liên tiếp không xếp hàng N lượt quét cả đoạn.
    /// 2. **Chạy off-main** qua `Task.detached`. An toàn, không phải giả thiết: chính
    ///    `QuickTranslationRuleEngine.rewrite` + `QuickTranslationDictionaryToken.resolve` đã chạy
    ///    off-main mỗi lần dựng chương qua `performChapterTranslationOffMainActor`, và
    ///    `QuickTranslationRuleTrace` là `Sendable`.
    /// 3. **Cancel lượt trước** để kết quả cũ không ghi đè kết quả mới.
    func refreshRuleTraces() {
        refreshDefinitionRules()
    }

    /// Gọi từ `.onChange(of: showingDefinitionSheet)` khi panel Dịch vừa đóng — một chỗ xử lý cho **mọi** đường
    /// đóng (vuốt xuống, chạm vùng mờ, lưu xong): có đổi dữ liệu rule thì dựng lại bản dịch.
    func handleDefinitionPanelClosed() {
        // Presentation con gắn trong sheet Dịch bị gỡ cùng sheet cha; trả cờ về để không treo ở trạng thái
        // "đang mở" (`ruleEditorMode != nil` chặn luôn bôi đen ở `onSelectionChangeInParagraph`).
        ruleEditorMode = nil
        showingSearchEnginesConfigSheet = false
        showingManageDefinitionsSheet = false
        definitionLookupRoute = nil
        definitionSession.cancel()
        let shouldRetranslate = didChangeRuleData
        didChangeRuleData = false
        if shouldRetranslate {
            applyTranslation()
        }
        // Cơ chế deferral giữ refresh lại trong lúc overlay còn mở, nên phải bung ở đây kể cả khi
        // không đổi gì (một thông báo từ điển có thể đã tới trong lúc sheet mở).
        checkAndReleaseDeferredTranslationRefresh()
    }

    // MARK: - Thao tác trên một rule

    func handleRuleAction(_ trace: QuickTranslationRuleTrace, _ action: ReaderRuleAction) {
        switch action {
        case .setDisabled(let disabled, let scope):
            performRuleCommand(.disable(pattern: trace.pattern, disabled: disabled, scope: scope),
                message: "\(disabled ? "Đã tắt" : "Đã bật") rule \(scope.longLabel.lowercased()).")

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
            moveRule(trace, to: destination)
        }
    }

    /// Chuyển một rule sang phạm vi còn lại = **ghi ở đích rồi xoá ở nguồn**.
    ///
    /// `QuickTranslationRuleTransfer.copy` cố ý là copy (xem doc của nó), nên phần "xoá ở nguồn" nằm ở
    /// đây chứ không sửa ngữ nghĩa của transfer — nút Chuyển của từ điển vẫn là copy như trước.
    ///
    /// Ghi ở đích **trước** để nếu lỗi thì rule vẫn còn nguyên ở nguồn: mất một rule người dùng tự viết
    /// là hỏng dữ liệu, còn tồn tại ở hai chỗ chỉ là dư và nói được thành lời.
    private func moveRule(_ trace: QuickTranslationRuleTrace, to destination: QuickTranslationRuleScope) {
        performRuleCommand(.move(pattern: trace.pattern, replacement: trace.replacement,
            from: trace.scope, to: destination), message: "Đã chuyển rule sang \(destination.longLabel.lowercased()).")
    }

    private func performRuleCommand(_ command: QuickTranslationRuleMutation.Command, message: String) {
        let session = definitionSession.identity
        Task { @MainActor in
            let result = await QuickTranslationRuleMutation.shared.perform(command)
            guard definitionSession.identity == session else { return }
            handleRuleOutcome(result, successMessage: message)
        }
    }

    /// Lưu rule mới từ nút `+` hoặc sửa rule từ Check rule. Trả `LoadOutcome` để sheet biết đóng hay giữ lại kèm lý do.
    func saveRuleFromEditor(
        mode: QuickTranslationRuleEditorSheet.Mode,
        pattern: String,
        replacement: String,
        scope: QuickTranslationRuleScope
    ) async -> QuickTranslationRuleStore.LoadOutcome {
        let session = definitionSession.identity
        let oldPattern: String?
        if case .edit(let pattern, _, _, _) = mode { oldPattern = pattern } else { oldPattern = nil }
        let outcome = await QuickTranslationRuleMutation.shared.perform(
            .upsert(oldPattern: oldPattern, pattern: pattern, replacement: replacement, scope: scope))
        if definitionSession.identity == session {
            handleRuleOutcome(outcome, successMessage: "Đã lưu rule vào \(scope.longLabel.lowercased()).")
        }
        return outcome
    }

    private func handleRuleOutcome(
        _ outcome: QuickTranslationRuleStore.LoadOutcome,
        successMessage: String
    ) {
        switch outcome {
        case .success:
            didChangeRuleData = true
            refreshRuleTraces()
            ToastManager.shared.show(message: successMessage, type: .success)
        case .rejected(let issues):
            let detail = issues.first.map { "dòng \($0.sourceLine) — \($0.code.rawValue)" } ?? "\(issues.count) dòng"
            ToastManager.shared.show(message: "Bộ rule có lỗi nặng (\(detail)); không đổi gì.", type: .error)
        case .failure(let message):
            ToastManager.shared.show(message: message, type: .error)
        }
    }

    // MARK: - Panel bôi đen

    /// Ba panel dùng chung vùng chọn nên chỉ một cái được mở. `nil` = đóng hết (dùng khi mở panel Dịch).
    enum SelectionPanel {
        case copyOriginal
        case junkDelete
    }

    func closeOtherSelectionPanels(except panel: SelectionPanel?) {
        if panel != .junkDelete { showingJunkDeleteSheet = false }
        if panel != .copyOriginal { showingCopyOriginalSheet = false }
        if panel != nil { showingDefinitionSheet = false }
    }

    func defaultRuleEditorScope(for mode: QuickTranslationRuleEditorSheet.Mode) -> QuickTranslationRuleScope {
        if case .edit(_, _, _, let scope) = mode { return scope }
        return .book(bookId)
    }

    /// Cụm chữ **gốc** đang chọn — dùng điền sẵn mẫu cho nút `+`.
    func selectedOriginalText() -> String {
        let ns = originalSentence as NSString
        let range = NSRange(location: selectedWordOffset, length: selectedWordLength)
        guard selectedWordOffset >= 0, selectedWordLength > 0, NSMaxRange(range) <= ns.length else { return "" }
        return ns.substring(with: range)
    }

    // MARK: - Lưu thay thế TTS từ sheet bôi đen

    /// Nhận kết quả từ `AddTTSReplacementSheet` và ghi vào **đúng tầng** người dùng chọn.
    ///
    /// Đặt ở file này (không phải `ReaderView.swift`) vì file đó **đã ở đúng baseline** `2053` dòng — thêm
    /// một dòng là tạo violation mới. Trùng `pattern` ở tầng đích thì `addRule` **đè** bản cũ, nên chỉ cần
    /// đổi nhãn toast giữa "Đã thêm" và "Đã cập nhật".
    func handleAddTTSReplacement(
        pattern: String,
        replacement: String,
        isEnabled: Bool,
        scope: TTSReplacementScope
    ) {
        let rule = TTSReplacementRule(pattern: pattern, replacement: replacement, isEnabled: isEnabled)
        let target: String?
        let layerName: String
        switch scope {
        case .book(let id):
            target = id
            layerName = "riêng của truyện"
        case .global:
            target = nil
            layerName = "chung"
        }
        let result = TTSReplacementManager.shared.addRule(rule, bookId: target)
        let action = result == .replaced ? "Đã cập nhật" : "Đã thêm"
        let statusSuffix = isEnabled ? "" : " (Đã tắt)"
        ToastManager.shared.show(
            message: "\(action) thay thế TTS (\(layerName)): '\(pattern)' → '\(replacement)'\(statusSuffix)",
            type: .success
        )
    }
}
