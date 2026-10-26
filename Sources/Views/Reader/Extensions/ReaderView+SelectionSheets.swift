import SwiftUI

/// Ba panel bôi đen của Reader — **Dịch**, **Xoá từ rác**, **Copy nội dung gốc** — trình bày bằng
/// `.sheet` gốc. Trước đây là overlay tự dựng trong `ZStack` của `ReaderView` (capsule giả,
/// `DragGesture` > 50pt thì đóng); nay có thanh kéo hệ thống, kéo bám ngón tay, chạm vùng mờ là đóng.
///
/// Bất biến:
/// - Mỗi sheet mở ở nấc cao đúng bằng nội dung (`fittedSheetDetent`), như panel cũ, vuốt lên được toàn màn.
///   Chiều cao đo được giữ ở `@State` của `ReaderView` để lần mở sau không nháy giá trị tạm.
/// - Không có nút ✕ ở tiêu đề (1.3.608): đóng bằng vuốt xuống / chạm vùng mờ.
/// - Hậu xử lý khi đóng nằm ở `.onChange(of: showingDefinitionSheet / showingJunkDeleteSheet)` của
///   `ReaderView`, áp cho **mọi** đường đóng (kéo xuống, chạm vùng mờ, lưu xong, nút trong panel). Không thêm đường
///   đóng nào khác ở đây.
/// - Copy gốc: `onDismiss` là đường **duy nhất** copy; nút Copy trong panel chỉ hạ cờ ⇒ không
///   bao giờ copy hai lần.
/// - Presentation con của panel Dịch (sửa/thêm rule, cấu hình công cụ tìm, tra cứu nhanh) phải gắn
///   **trong** sheet Dịch: một view đang trình bày sheet thì không trình bày thêm được sheet thứ hai.
///   Tra cứu từ nút "Tìm" của menu bôi đen (lúc chưa có sheet nào) vẫn đi `lookupRoute` ở `ReaderView`.
///
/// Panel Dịch: `ruleTraces` được `refreshRuleTraces()` làm mới khi mở panel **hoặc** khi dữ liệu rule
/// (chung hoặc riêng của truyện đang đọc) thay đổi. Khi mở rộng / thu hẹp vùng chọn token, rule traces
/// **không** load lại. Đóng panel mà `didChangeRuleData` bật thì phải `applyTranslation()` — xem
/// `openDefinitionPanel()` / `handleDefinitionPanelClosed()` ở `ReaderView+RuleTools.swift`.
@MainActor
extension ReaderView {

    /// Gắn ba sheet lên tầng trình bày của `ReaderView` (gọi từ `readerSheetLayer`). Mỗi sheet một
    /// property riêng để trình biên dịch suy luận kiểu từng phần, không vượt ngân sách type-check.
    func withSelectionSheets<Base: View>(_ base: Base) -> some View {
        base
            .sheet(isPresented: $showingDefinitionSheet) {
                definitionSheetContent
            }
            .sheet(isPresented: $showingJunkDeleteSheet) {
                junkDeleteSheetContent
            }
            // `closeOtherSelectionPanels` cũng hạ cờ này nên cũng copy. Chấp nhận được: khi một sheet đang
            // mở thì menu bôi đen bị che, không mở được panel khác để rơi vào đường đó.
            .sheet(isPresented: $showingCopyOriginalSheet, onDismiss: { commitCopyOriginal() }) {
                copyOriginalSheetContent
            }
    }

    /// Xám đậm cho **mọi** theme, và ba view nội dung không tô nền riêng ⇒ vùng đệm và nội dung cùng một màu
    /// (1.3.608). Không theo theme Sáng/Trầm ấm: chữ và chip của panel làm cho nền tối.
    private var selectionSheetBackground: Color {
        Color(red: 0.12, green: 0.12, blue: 0.14)
    }

    // MARK: - Dịch

    private var definitionSheetContent: some View {
        definitionPanelView
            .padding([.horizontal, .bottom])
            .fittedSheetDetent(height: $definitionSheetHeight, background: selectionSheetBackground)
            .sheet(item: $ruleEditorMode) { mode in
                QuickTranslationRuleEditorSheet(
                    mode: mode,
                    defaultScope: defaultRuleEditorScope(for: mode),
                    contextBookId: bookId
                ) { pattern, replacement, scope in
                    await saveRuleFromEditor(mode: mode, pattern: pattern, replacement: replacement, scope: scope)
                }
            }
            .sheet(isPresented: $showingSearchEnginesConfigSheet, onDismiss: { searchEngines = SearchEngine.loadEngines() }) {
                NavigationStack {
                    SearchEnginesConfigView().toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Xong") { showingSearchEnginesConfigSheet = false } }
                    }
                }
            }
            .fullScreenCover(item: $definitionLookupRoute) { route in
                BypassWebView(
                    urlString: route.urlString
                )
            }
    }

    private var definitionPanelView: ReaderDefinitionOverlayView {
        ReaderDefinitionOverlayView(
            isPresented: $showingDefinitionSheet,
            selectedTheme: selectedTheme,
            originalSentence: originalSentence,
            selectedWordOffset: $selectedWordOffset,
            selectedWordLength: $selectedWordLength,
            translationTokens: translationTokens,
            customMeaning: definitionMeaningBinding,
            saveAsNameType: $saveAsNameType,
            saveToBookSpecific: $saveToBookSpecific,
            pinnedSaveAsNameType: pinnedSaveAsNameType,
            pinnedSaveToBookSpecific: pinnedSaveToBookSpecific,
            onPinNameType: { isName in
                pinnedSaveAsNameType = isName
                saveAsNameType = isName
                ToastManager.shared.show(message: "Đã ghim mặc định Loại: \(isName ? "Names" : "VP")", type: .success)
            },
            onPinScope: { isBook in
                pinnedSaveToBookSpecific = isBook
                saveToBookSpecific = isBook
                ToastManager.shared.show(message: "Đã ghim mặc định Phạm vi: \(isBook ? "Riêng" : "Chung")", type: .success)
            },
            suggestionChips: suggestionChips,
            searchEngines: searchEngines,
            selectedTextForDefinition: selectedTextForDefinition,
            bookId: bookId,
            dictionaryMatches: $dictionaryMatches,
            translationMode: $translationMode,
            showingManageDefinitionsSheet: $showingManageDefinitionsSheet,
            onExpandSelectionLeft: expandSelectionLeft,
            onShrinkSelectionLeft: shrinkSelectionLeft,
            onShrinkSelectionRight: shrinkSelectionRight,
            onExpandSelectionRight: expandSelectionRight,
            onUpdateEditorFromSelection: updateEditorFromSelection,
            onFormatMeaning: formatMeaning,
            onSaveDefinition: saveDefinition,
            // Bọc closure chứ **không** truyền thẳng `performQuickLookup`: hàm đó có tham số
            // `query` mặc định, mà một function reference kèm default argument **không** tự
            // chuyển sang `(SearchEngine) -> Void` — truyền thẳng là lỗi biên dịch.
            onPerformQuickLookup: { performQuickLookup(using: $0) },
            onOpenSearchEngineConfig: {
                showingSearchEnginesConfigSheet = true
            },
            // Overlay chỉ gọi closure này sau khi màn quản lý định nghĩa báo có thay đổi ⇒
            // tính lại chip cùng lúc với `dictionaryMatches` để gợi ý không bị cũ.
            onGetDictionaryMatches: { _ in dictionaryMatches },
            onGetHanViet: { getHanViet(for: $0) },
            onApplyTranslation: { loadDefinitionData() },
            ruleTraces: ruleTraces,
            focusedRuleTraceID: $focusedRuleTraceID,
            isRuleFeatureEnabled: definitionSession.rulesEnabled,
            hasAnyRuleSet: definitionSession.hasRules,
            isLoadingDefinition: definitionSession.loading,
            isLoadingRules: definitionSession.loadingRules,
            isSaving: definitionSession.saving,
            onRuleAction: { trace, action in handleRuleAction(trace, action) },
            // Điền sẵn **cả hai** ô: mẫu = cụm gốc đang chọn, nghĩa = đúng chữ đang có trong ô
            // nhập nghĩa của panel này (kể cả nghĩa người dùng vừa sửa tay).
            onAddRule: {
                ruleEditorMode = .add(
                    prefilledPattern: selectedOriginalText(),
                    prefilledReplacement: customMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        )
    }

    // MARK: - Xoá từ rác

    private var junkDeleteSheetContent: some View {
        junkDeletePanelView
            .padding([.horizontal, .bottom])
            .fittedSheetDetent(height: $junkDeleteSheetHeight, background: selectionSheetBackground)
    }

    private var junkDeletePanelView: ReaderJunkDeleteOverlayView {
        ReaderJunkDeleteOverlayView(
            isPresented: $showingJunkDeleteSheet,
            selectedTheme: selectedTheme,
            originalSentence: originalSentence,
            selectedWordOffset: $selectedWordOffset,
            selectedWordLength: $selectedWordLength,
            translationTokens: translationTokens,
            junkPatternInput: $junkPatternInput,
            onExpandSelectionLeft: expandSelectionLeft,
            onShrinkSelectionLeft: shrinkSelectionLeft,
            onShrinkSelectionRight: shrinkSelectionRight,
            onExpandSelectionRight: expandSelectionRight,
            onUpdateEditorFromSelection: updateEditorFromSelection,
            onConfirmDelete: { pattern in
                confirmDeleteJunk(pattern)
            },
            onCancel: {
                showingJunkDeleteSheet = false
            }
        )
    }

    // MARK: - Copy nội dung gốc

    private var copyOriginalSheetContent: some View {
        copyOriginalPanelView
            .padding([.horizontal, .bottom])
            .fittedSheetDetent(height: $copyOriginalSheetHeight, background: selectionSheetBackground)
    }

    private var copyOriginalPanelView: ReaderCopyOriginalOverlayView {
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
            // Chỉ hạ cờ: việc copy nằm ở `onDismiss` của sheet (đường copy duy nhất).
            onCommit: { showingCopyOriginalSheet = false }
        )
    }
}
