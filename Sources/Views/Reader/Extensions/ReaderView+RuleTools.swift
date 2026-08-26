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
        updateEditorFromSelection()
        closeOtherSelectionPanels(except: .copyOriginal)
        showingCopyOriginalSheet = true
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

    func openRuleTracePanel() {
        updateEditorFromSelection()
        closeOtherSelectionPanels(except: .ruleTrace)
        didChangeRuleData = false
        focusedRuleTraceID = nil
        refreshRuleTraces()
        showingRuleTraceSheet = true
    }

    /// Chẩn đoán lại **cả đoạn** rồi giữ lại focus nếu chip cũ còn tồn tại.
    func refreshRuleTraces() {
        let selection = NSRange(location: max(0, selectedWordOffset), length: max(0, selectedWordLength))
        ruleTraces = QuickTranslationRuleDiagnostics.diagnose(
            text: originalSentence,
            bookId: bookId,
            selection: selection
        )
        if let focusedRuleTraceID, !ruleTraces.contains(where: { $0.id == focusedRuleTraceID }) {
            self.focusedRuleTraceID = nil
        }
    }

    /// Đóng sheet check rule. Có đổi dữ liệu rule thì **dịch lại**; không đổi gì thì không dựng lại.
    func closeRuleTracePanel() {
        showingRuleTraceSheet = false
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

    func handleRuleAction(_ trace: QuickTranslationRuleTrace, _ action: ReaderRuleTraceOverlayView.RuleAction) {
        switch action {
        case .setDisabled(let disabled, let scope):
            let outcome = QuickTranslationRuleDisableStore.shared.setDisabled(
                disabled,
                pattern: trace.pattern,
                scope: scope
            )
            switch outcome {
            case .success:
                didChangeRuleData = true
                refreshRuleTraces()
                let verb = disabled ? "Đã tắt" : "Đã bật"
                let target = scope.isGlobal ? "cho mọi truyện" : "cho truyện này"
                ToastManager.shared.show(message: "\(verb) rule \(target).", type: .info)
            case .failure(let message):
                ToastManager.shared.show(message: message, type: .error)
            }

        case .delete:
            let outcome: QuickTranslationRuleStore.LoadOutcome
            switch trace.scope {
            case .global:
                outcome = QuickTranslationRuleStore.shared.deleteRule(pattern: trace.pattern)
            case .book(let identifier):
                outcome = QuickTranslationRuleBookStore.shared.deleteRule(
                    pattern: trace.pattern,
                    bookId: identifier
                )
            }
            handleRuleOutcome(outcome, successMessage: "Đã xoá rule khỏi \(trace.scope.longLabel.lowercased()).")
        }
    }

    /// Lưu rule mới từ nút `+`. Trả `LoadOutcome` để sheet biết đóng hay giữ lại kèm lý do.
    func saveRuleFromEditor(
        pattern: String,
        replacement: String,
        scope: QuickTranslationRuleScope
    ) -> QuickTranslationRuleStore.LoadOutcome {
        let outcome: QuickTranslationRuleStore.LoadOutcome
        switch scope {
        case .global:
            outcome = QuickTranslationRuleStore.shared.addOrOverwriteRule(
                pattern: pattern,
                replacement: replacement
            )
        case .book(let identifier):
            outcome = QuickTranslationRuleBookStore.shared.addOrOverwriteRule(
                pattern: pattern,
                replacement: replacement,
                bookId: identifier
            )
        }
        handleRuleOutcome(outcome, successMessage: "Đã lưu rule vào \(scope.longLabel.lowercased()).")
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

    /// Bốn panel dùng chung vùng chọn nên chỉ một cái được mở.
    enum SelectionPanel {
        case copyOriginal
        case ruleTrace
    }

    func closeOtherSelectionPanels(except panel: SelectionPanel) {
        showingDefinitionSheet = false
        showingJunkDeleteSheet = false
        if panel != .copyOriginal { showingCopyOriginalSheet = false }
        if panel != .ruleTrace { showingRuleTraceSheet = false }
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

            if showingRuleTraceSheet {
                bottomPanel(in: geometry, onDismiss: { closeRuleTracePanel() }) {
                    ReaderRuleTraceOverlayView(
                        paragraphIndex: editingParagraphIndex ?? 0,
                        bookId: bookId,
                        originalSentence: originalSentence,
                        selectedWordOffset: $selectedWordOffset,
                        selectedWordLength: $selectedWordLength,
                        traces: ruleTraces,
                        focusedTraceID: $focusedRuleTraceID,
                        isRuleFeatureEnabled: QuickTranslationRuleStore.shared.isEnabled,
                        hasAnyRuleSet: QuickTranslationRuleStore.shared.currentSnapshot != nil
                            || QuickTranslationRuleBookStore.shared.snapshot(for: bookId) != nil,
                        onAddRule: { ruleEditorMode = .add(prefilledPattern: selectedOriginalText()) },
                        onRuleAction: { trace, action in handleRuleAction(trace, action) },
                        onShowGuide: { showingRuleGuide = true },
                        onClose: { closeRuleTracePanel() }
                    )
                }
                .zIndex(8)
            }
        }
        .sheet(isPresented: $showingRuleGuide) {
            ReaderRuleTraceGuideSheet()
        }
        .sheet(item: $ruleEditorMode) { mode in
            QuickTranslationRuleEditorSheet(
                mode: mode,
                defaultScope: .book(bookId),
                contextBookId: bookId
            ) { pattern, replacement, scope in
                saveRuleFromEditor(pattern: pattern, replacement: replacement, scope: scope)
            }
        }
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
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                        .fill(selectedTheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color.white)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: -4)
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
