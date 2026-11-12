import SwiftUI

/// Màn **Dịch** khi chạm một khối dịch của truyện tranh (1.3.837) — đúng bảng `ReaderDefinitionOverlayView` của Reader:
/// chọn cụm (chạm chữ, mũi tên nới / thu), nghĩa VP / Hán-Việt, chip gợi ý, quản lý nghĩa (⚙), lưu Name / VP riêng / chung
/// kèm ghim mặc định (cùng khoá `@AppStorage` với Reader), chip rule + thao tác rule, tra nhanh bằng công cụ tìm. Câu gốc =
/// chữ Trung OCR của khối, lúc mở chọn sẵn cả câu.
///
/// Phần lõi dùng lại nguyên của Reader: `ReaderDefinitionOverlayView`, `ReaderDefinitionWorker`, `ReaderDefinitionSession`,
/// `QuickTranslationRuleEditorSheet`, `QuickTranslationRuleMutation`, `TranslationManager.saveCustomEntry`. Phần ráp nối của
/// Reader nằm trong `ReaderView` (+Selection, +RuleTools, +DefinitionLoading, +SelectionSheets) và gắn chặt vào trạng thái
/// của nó, nên màn này **chép lại** phần ráp nối (`+Selection`, `+Rules`) thay vì sửa `ReaderView` — sửa logic panel Dịch
/// của Reader thì xem cả hai file đó.
///
/// Trạng thái là `@State` không `private` để hai file `+` đọc được (như `ReaderView`). Lưu name / đổi rule ⇒ thông báo từ
/// điển / rule ⇒ màn đọc dịch lại bong bóng; chỗ trình bày còn gọi lại khi sheet đóng cho chắc.
@MainActor
struct ComicDefinitionSheet: View {
    /// Một lần mở: câu gốc + truyện (`.sheet(item:)`).
    struct Request: Identifiable {
        let id = UUID()
        let sentence: String
        let bookId: String
        let convertsTraditional: Bool
    }

    let request: Request

    @Environment(\.dismiss) var dismiss
    @AppStorage("pinnedSaveToBookSpecific") var pinnedSaveToBookSpecific = true
    @AppStorage("pinnedSaveAsNameType") var pinnedSaveAsNameType = false

    @State var selectedWordOffset = 0
    @State var selectedWordLength: Int
    @State var selectedTextForDefinition: String
    @State var translationTokens: [TranslationWordToken] = []
    @State var customMeaning = ""
    @State var saveAsNameType = false
    @State var saveToBookSpecific = true
    @State var suggestionChips: [SuggestionChip] = []
    @State var searchEngines: [SearchEngine] = []
    @State var dictionaryMatches: [DictionaryMatchInfo] = []
    /// "VP" (VietPhrase) hoặc "HV" (Hán-Việt) — như Reader, không nhớ giữa các lần mở.
    @State var translationMode = "VP"
    @State var showingManageDefinitionsSheet = false
    @State var ruleTraces: [QuickTranslationRuleTrace] = []
    @State var focusedRuleTraceID: String?
    @State var definitionSession = ReaderDefinitionSession()
    @State var ruleEditorMode: QuickTranslationRuleEditorSheet.Mode?
    @State var showingSearchEnginesConfigSheet = false
    @State var lookupRoute: ReaderLookupRoute?
    @State private var sheetHeight: CGFloat = 0
    @State private var hasStarted = false

    /// Cùng màu nền với ba panel bôi đen của Reader (`ReaderView+SelectionSheets.selectionSheetBackground`).
    private static let background = Color(red: 0.12, green: 0.12, blue: 0.14)

    var sentence: String { request.sentence }
    var bookId: String { request.bookId }

    init(request: Request) {
        self.request = request
        let length = (request.sentence as NSString).length
        _selectedWordLength = State(initialValue: max(1, length))
        _selectedTextForDefinition = State(initialValue: request.sentence)
    }

    var body: some View {
        overlay
            .padding([.horizontal, .bottom])
            .fittedSheetDetent(height: $sheetHeight, background: Self.background)
            .preferredColorScheme(.dark)
            // Presentation con gắn **trong** sheet này (một view đang trình bày sheet thì không trình bày thêm được).
            .sheet(item: $ruleEditorMode) { mode in
                Group {
                    QuickTranslationRuleEditorSheet(
                        mode: mode,
                        defaultScope: defaultRuleEditorScope(for: mode),
                        contextBookId: bookId
                    ) { pattern, replacement, scope, replacing in
                        await saveRuleFromEditor(pattern: pattern, replacement: replacement, scope: scope, replacing: replacing)
                    }
                }
                .appGlassSheet()
            }
            .sheet(isPresented: $showingSearchEnginesConfigSheet, onDismiss: { searchEngines = SearchEngine.loadEngines() }) {
                Group {
                    NavigationStack { SearchEnginesConfigView(isPresentedAsSheet: true) }
                        .presentationDragIndicator(.visible)
                }
                .appGlassSheet()
            }
            .fullScreenCover(item: $lookupRoute) { route in
                BypassWebView(urlString: route.urlString)
            }
            .onAppear(perform: start)
            .onDisappear { definitionSession.cancel() }
    }

    private var overlay: ReaderDefinitionOverlayView {
        ReaderDefinitionOverlayView(
            isPresented: Binding(get: { true }, set: { if !$0 { dismiss() } }),
            selectedTheme: .dark,
            originalSentence: sentence,
            selectedWordOffset: $selectedWordOffset,
            selectedWordLength: $selectedWordLength,
            translationTokens: translationTokens,
            customMeaning: meaningBinding,
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
            onFormatMeaning: { ReaderSelectionCoordinator.shared.formatMeaning($0, style: $1) },
            onSaveDefinition: saveDefinition,
            onPerformQuickLookup: { performQuickLookup(using: $0) },
            onOpenSearchEngineConfig: { showingSearchEnginesConfigSheet = true },
            onGetDictionaryMatches: { _ in dictionaryMatches },
            onGetHanViet: { ReaderSelectionCoordinator.shared.getHanViet(for: $0) },
            onApplyTranslation: { loadDefinitionData() },
            ruleTraces: ruleTraces,
            focusedRuleTraceID: $focusedRuleTraceID,
            isRuleFeatureEnabled: definitionSession.rulesEnabled,
            hasAnyRuleSet: definitionSession.hasRules,
            isLoadingDefinition: definitionSession.loading,
            isLoadingRules: definitionSession.loadingRules,
            isSaving: definitionSession.saving,
            onRuleAction: { trace, action in handleRuleAction(trace, action) },
            onAddRule: {
                ruleEditorMode = .add(
                    prefilledPattern: selectedOriginalText(),
                    prefilledReplacement: customMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        )
    }

    /// Như `openDefinitionPanel()` của Reader: mở là tra cụm đang chọn + quét rule của cả câu.
    private func start() {
        guard !hasStarted else { return }
        hasStarted = true
        searchEngines = SearchEngine.loadEngines()
        definitionSession.begin()
        focusedRuleTraceID = nil
        ruleTraces = []
        updateEditorFromSelection()
        refreshDefinitionRules()
    }
}
