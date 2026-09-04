import SwiftUI

/// Panel **Dịch** của Reader dựng ở đây, không ở `ReaderView.swift`.
///
/// Hai lý do: `ReaderView.swift` sát baseline dòng của `check_architecture.py` nên chỉ được giảm, và
/// từ 1.3.334 panel này nhận thêm sáu tham số của Check rule (gộp vào đây, không còn panel riêng).
///
/// Bất biến: `ruleTraces` phải được `refreshRuleTraces()` làm mới **trước** khi mở panel và mỗi lần
/// vùng chọn đổi; đóng panel mà `didChangeRuleData` bật thì phải `applyTranslation()` — xem
/// `openDefinitionPanel()` / `closeDefinitionPanel()` ở `ReaderView+RuleTools.swift`.
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
                    customMeaning: $customMeaning,
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
                    onPerformQuickLookup: performQuickLookup,
                    onOpenSearchEngineConfig: {
                        showingSearchEnginesConfigSheet = true
                    },
                    // Overlay chỉ gọi closure này sau khi màn quản lý định nghĩa báo có thay đổi ⇒
                    // tính lại chip cùng lúc với `dictionaryMatches` để gợi ý không bị cũ.
                    onGetDictionaryMatches: { word in
                        refreshSuggestionChips(for: word)
                        return getDictionaryMatches(for: word)
                    },
                    onGetHanViet: { getHanViet(for: $0) },
                    onApplyTranslation: applyTranslation,
                    ruleTraces: ruleTraces,
                    focusedRuleTraceID: $focusedRuleTraceID,
                    isRuleFeatureEnabled: QuickTranslationRuleStore.shared.isEnabled,
                    hasAnyRuleSet: QuickTranslationRuleStore.shared.currentSnapshot != nil
                        || QuickTranslationRuleBookStore.shared.snapshot(for: bookId) != nil,
                    onRuleAction: { trace, action in handleRuleAction(trace, action) },
                    onAddRule: { ruleEditorMode = .add(prefilledPattern: selectedOriginalText()) }
                )
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
