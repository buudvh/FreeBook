import SwiftUI

/// Hai công cụ mới của menu bôi đen: **Copy nội dung gốc** và **Check rule**.
///
/// Đặt ở file riêng vì `ReaderView.swift` đã vượt baseline dòng của `check_architecture.py` nên chỉ
/// được giảm; ở đó chỉ còn phần khai `@State` và một dòng gọi `ruleToolsOverlay(in:)`.
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

    /// **Một** đường ra duy nhất cho panel copy gốc: nút Copy, nút ✕, kéo xuống và tap ra ngoài đều
    /// gọi hàm này. Bốn đường đóng là chỗ dễ bỏ sót nhất của yêu cầu "đóng là copy".
    func commitCopyOriginal() {
        let ns = originalSentence as NSString
        let range = NSRange(location: selectedWordOffset, length: selectedWordLength)
        showingCopyOriginalSheet = false

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

    /// Đóng panel Dịch. Chỉ hạ cờ — phần "dịch lại khi rule đã đổi" nằm ở `.onChange(of:
    /// showingDefinitionSheet)` của `ReaderView`, vì nút ✕ trong panel đóng bằng binding `isPresented`
    /// nên không đi qua hàm này. Một chỗ xử lý cho **mọi** đường đóng.
    func closeDefinitionPanel() {
        showingDefinitionSheet = false
    }

    /// Gọi từ `.onChange` khi panel Dịch vừa đóng: có đổi dữ liệu rule thì dựng lại bản dịch.
    func handleDefinitionPanelClosed() {
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

    // MARK: - Overlay

    /// Ba panel dùng chung vùng chọn nên chỉ một cái được mở. `nil` = đóng hết (dùng khi mở panel Dịch).
    enum SelectionPanel {
        case copyOriginal
    }

    func closeOtherSelectionPanels(except panel: SelectionPanel?) {
        showingJunkDeleteSheet = false
        if panel != .copyOriginal { showingCopyOriginalSheet = false }
        if panel != nil { showingDefinitionSheet = false }
    }

    @ViewBuilder
    func ruleToolsOverlay(in geometry: GeometryProxy) -> some View {
        ZStack {
            if showingCopyOriginalSheet {
                bottomPanel(in: geometry, onDismiss: { commitCopyOriginal() }) {
                    ReaderCopyOriginalOverlayView(
                        originalSentence: originalSentence,
                        selectedWordOffset: $selectedWordOffset,
                        selectedWordLength: $selectedWordLength,
                        translationTokens: translationTokens,
                        onExpandSelectionLeft: expandSelectionLeft,
                        onShrinkSelectionLeft: shrinkSelectionLeft,
                        onShrinkSelectionRight: shrinkSelectionRight,
                        onExpandSelectionRight: expandSelectionRight,
                        onUpdateEditorFromSelection: updateEditorFromSelection,
                        onCommit: { commitCopyOriginal() }
                    )
                }
                .zIndex(7)
            }

        }
        .sheet(item: $ruleEditorMode) { mode in
            QuickTranslationRuleEditorSheet(
                mode: mode,
                defaultScope: defaultRuleEditorScope(for: mode),
                contextBookId: bookId
            ) { pattern, replacement, scope in
                await saveRuleFromEditor(mode: mode, pattern: pattern, replacement: replacement, scope: scope)
            }
        }
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

    /// Khuôn panel đáy dùng chung, mượn nguyên bố cục panel Xoá từ rác: vùng trống phía trên bắt tap
    /// để đóng, panel bo góc trên, kéo xuống > 50pt là đóng. `onDismiss` là **cùng một** hàm với nút
    /// đóng trong panel, nên không có đường ra nào bỏ sót việc phải làm khi đóng.
    @ViewBuilder
    private func bottomPanel<Content: View>(
        in geometry: GeometryProxy,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        withAnimation { onDismiss() }
                    }
                )

            content()
                .padding([.horizontal, .bottom])
                .background { selectedTheme.panelBackground() }
                .einkShadow(radius: 10, y: -4)
                .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 8)
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            if value.translation.height > 50 {
                                withAnimation { onDismiss() }
                            }
                        }
                )
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
