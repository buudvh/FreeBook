import SwiftUI

/// Panel **Dịch** của Reader dựng ở đây, không ở `ReaderView.swift`.
///
/// Hai lý do: `ReaderView.swift` sát baseline dòng của `check_architecture.py` nên chỉ được giảm, và
/// từ 1.3.334 panel này nhận thêm sáu tham số của Check rule (gộp vào đây, không còn panel riêng).
///
/// Bất biến: `ruleTraces` được `refreshRuleTraces()` làm mới khi mở panel **và** mỗi lần vùng chọn đổi
/// (từ 1.3.339 việc này thực sự được cài, ở cuối `updateEditorFromSelection()`; hàm chẩn đoán có
/// debounce 150 ms và chạy off-main nên nới/thu liên tục không thành N lượt quét cả đoạn). Đóng panel
/// mà `didChangeRuleData` bật thì phải `applyTranslation()` — xem `openDefinitionPanel()` /
/// `closeDefinitionPanel()` ở `ReaderView+RuleTools.swift`.
@MainActor
extension ReaderView {

    @ViewBuilder
    internal func definitionPanelOverlay(in geometry: GeometryProxy) -> some View {
        if showingDefinitionSheet {
            VStack(spacing: 0) {
                // Vùng trống phía trên bắt tap để đóng panel dịch
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            withAnimation {
                                closeDefinitionPanel()
                            }
                        }
                    )

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
                    onPinNameType: { (isName: Bool) in
                        pinnedSaveAsNameType = isName
                        saveAsNameType = isName
                        ToastManager.shared.show(message: "Đã ghim mặc định Loại: \(isName ? "Names" : "VP")", type: .success)
                    },
                    onPinScope: { (isBook: Bool) in
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
                    onPerformQuickLookup: { (engine: SearchEngine) in performQuickLookup(using: engine) },
                    onOpenSearchEngineConfig: {
                        showingSearchEnginesConfigSheet = true
                    },
                    // Overlay chỉ gọi closure này sau khi màn quản lý định nghĩa báo có thay đổi ⇒
                    // tính lại chip cùng lúc với `dictionaryMatches` để gợi ý không bị cũ.
                    onGetDictionaryMatches: { (_: String) -> [DictionaryMatchInfo] in dictionaryMatches },
                    onGetHanViet: { (text: String) -> String in getHanViet(for: text) },
                    onApplyTranslation: { loadDefinitionData() },
                    ruleTraces: ruleTraces,
                    focusedRuleTraceID: $focusedRuleTraceID,
                    isRuleFeatureEnabled: definitionSession.rulesEnabled,
                    hasAnyRuleSet: definitionSession.hasRules,
                    isLoadingDefinition: definitionSession.loading,
                    isLoadingRules: definitionSession.loading || definitionSession.loadingRules,
                    isSaving: definitionSession.saving,
                    isDefinitionCurrent: isDefinitionDataCurrent(),
                    onRuleAction: { (trace: QuickTranslationRuleTrace, action: ReaderRuleAction) in handleRuleAction(trace, action) },
                    // Điền sẵn **cả hai** ô: mẫu = cụm gốc đang chọn, nghĩa = đúng chữ đang có trong ô
                    // nhập nghĩa của panel này (kể cả nghĩa người dùng vừa sửa tay).
                    onAddRule: {
                        ruleEditorMode = .add(
                            prefilledPattern: selectedOriginalText(),
                            prefilledReplacement: customMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                )
                .padding(.horizontal)
                .padding(.bottom)
                .background { selectedTheme.panelBackground() }
                .einkShadow(radius: 10, y: -4)
                .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 8)
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            if value.translation.height > 50 {
                                withAnimation {
                                    closeDefinitionPanel()
                                }
                            }
                        }
                )
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(5)
        }
    }
}
