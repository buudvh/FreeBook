import SwiftUI

public enum SuggestionChipCategory: String, Sendable {
    case name       // Từ điển Names -> Màu Đỏ
    case vietPhrase // Từ điển VietPhrase -> Màu Xanh Dương
    case hanViet    // Phiên âm Hán Việt -> Màu Xám

    public var borderColor: Color {
        switch self {
        case .name: return Color.red.opacity(0.45)
        case .vietPhrase: return Color.blue.opacity(0.45)
        case .hanViet: return Color.gray.opacity(0.45)
        }
    }

    public var textColor: Color {
        switch self {
        case .name: return Color(red: 1.0, green: 0.45, blue: 0.45)
        case .vietPhrase: return Color(red: 0.45, green: 0.82, blue: 1.0)
        case .hanViet: return Color(red: 0.75, green: 0.75, blue: 0.75)
        }
    }
}

public struct SuggestionChip: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let text: String
    public let category: SuggestionChipCategory

    public init(text: String, category: SuggestionChipCategory) {
        self.text = text
        self.category = category
    }
}

struct ReaderDefinitionOverlayView: View {
    @Binding var isPresented: Bool
    let selectedTheme: ReaderTheme
    let originalSentence: String
    @Binding var selectedWordOffset: Int
    @Binding var selectedWordLength: Int
    let translationTokens: [TranslationWordToken]
    @Binding var customMeaning: String
    @Binding var saveAsNameType: Bool
    @Binding var saveToBookSpecific: Bool
    let pinnedSaveAsNameType: Bool
    let pinnedSaveToBookSpecific: Bool
    let onPinNameType: (Bool) -> Void
    let onPinScope: (Bool) -> Void
    let suggestionChips: [SuggestionChip]
    let searchEngines: [SearchEngine]
    let selectedTextForDefinition: String
    let bookId: String
    @Binding var dictionaryMatches: [DictionaryMatchInfo]
    @Binding var translationMode: String
    @Binding var showingManageDefinitionsSheet: Bool

    let onExpandSelectionLeft: () -> Void
    let onShrinkSelectionLeft: () -> Void
    let onShrinkSelectionRight: () -> Void
    let onExpandSelectionRight: () -> Void
    let onUpdateEditorFromSelection: () -> Void
    let onFormatMeaning: (String, String) -> String
    let onSaveDefinition: () -> Void
    let onPerformQuickLookup: (SearchEngine) -> Void
    let onOpenSearchEngineConfig: () -> Void
    let onGetDictionaryMatches: (String) -> [DictionaryMatchInfo]
    let onGetHanViet: (String) -> String
    var onApplyTranslation: (() -> Void)? = nil

    // Check rule gộp vào đây ở 1.3.334 — xem `ReaderDefinitionOverlayView+Rules.swift`.
    let ruleTraces: [QuickTranslationRuleTrace]
    @Binding var focusedRuleTraceID: String?
    let isRuleFeatureEnabled: Bool
    let hasAnyRuleSet: Bool
    var isLoadingDefinition = false
    var isLoadingRules = false
    var isSaving = false
    var isDefinitionCurrent = true
    let onRuleAction: (QuickTranslationRuleTrace, ReaderRuleAction) -> Void
    let onAddRule: () -> Void

    /// `@State` phải khai trong struct chính: extension không thêm được stored property.
    @State internal var ruleActionTarget: QuickTranslationRuleTrace? = nil
    @State internal var showingRuleActions = false

    /// Đọc thẳng khoá `UserDefaults` để panel Dịch tự cập nhật màu khi đổi chế độ E-Ink.
    @AppStorage(EInkModeSettings.Key.enabled) var isEInkEnabled = false
    @AppStorage(EInkModeSettings.Key.paperColor) var paperColorRaw = EInkModeSettings.EInkPaperColor.gray.rawValue

    internal var paper: Color {
        EInkPalette.paperColor(for: EInkModeSettings.EInkPaperColor(rawValue: paperColorRaw) ?? .gray)
    }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                dragIndicatorView
                headerView
                originalSentenceRowView
                translatedTokensRowView
                customMeaningInputView
                ruleMeaningRowView
            }
            Group {
                suggestionChipsView
                ruleChipRowView
                combinedFormattingAndPickersView
                updateButtonView
                Divider()
                quickLookupLinksView
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background((isEInkEnabled ? paper : Color(uiColor: .systemBackground)).onTapGesture { hideKeyboard() })
        .confirmationDialog(
            ruleActionTarget.map { "Rule dòng \($0.sourceLine) · \($0.scope.longLabel)" } ?? "Rule",
            isPresented: $showingRuleActions,
            titleVisibility: .visible,
            presenting: ruleActionTarget
        ) { trace in
            ruleActionButtons(for: trace)
        } message: { trace in
            Text("\(trace.pattern)\n→ \(trace.replacement)")
        }
        .sheet(isPresented: $showingManageDefinitionsSheet) {
            ManageDefinitionsView(
                word: selectedTextForDefinition,
                bookId: bookId,
                matches: $dictionaryMatches,
                onChanged: {
                    onApplyTranslation?()
                }
            )
        }
    }

    private var dragIndicatorView: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
    }

    private var headerView: some View {
        HStack {
            Text("Dịch")
                .font(.headline)
            Spacer()
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title2)
            }
        }
    }

    private var originalSentenceRowView: some View {
        let ruleRange = focusedRuleRange
        return HStack(spacing: 4) {
            HStack(spacing: 3) {
                Button(action: onExpandSelectionLeft) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(isEInkEnabled ? paper : Color.blue.opacity(0.1), in: Circle())
                        .overlay { if isEInkEnabled { Circle().strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
                }
                Button(action: onShrinkSelectionLeft) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(isEInkEnabled ? paper : Color.blue.opacity(0.1), in: Circle())
                        .overlay { if isEInkEnabled { Circle().strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
                }
            }
            .foregroundColor(.blue)
            .einkAccentForeground(.blue)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        let nsSentence = originalSentence as NSString
                        ForEach(0..<nsSentence.length, id: \.self) { index in
                            let char = nsSentence.substring(with: NSRange(location: index, length: 1))
                            let isSelected = (index >= selectedWordOffset && index < selectedWordOffset + selectedWordLength)
                            // Nền nhạt = cụm của rule đang chọn ở dải chip. Lớp này **độc lập** với vùng
                            // chọn nên bấm chip không đổi cụm đang tra nghĩa.
                            let inRuleSpan = ruleRange.map { index >= $0.location && index < NSMaxRange($0) } ?? false
                            Text(char)
                                .font(.body)
                                .bold(isSelected)
                                .underline(inRuleSpan && isEInkEnabled)
                                .foregroundColor(isSelected ? (isEInkEnabled ? .white : .blue) : .primary)
                                .padding(.horizontal, inRuleSpan ? 1 : 0)
                                .background(
                                    isSelected
                                        ? (isEInkEnabled ? Color.black : Color.blue.opacity(0.1))
                                        : (inRuleSpan ? (isEInkEnabled ? Color.clear : Color.green.opacity(0.22)) : Color.clear),
                                    in: RoundedRectangle(cornerRadius: 3)
                                )
                                .cornerRadius(3)
                                .id("orig-\(index)")
                                .onTapGesture {
                                    selectedWordOffset = index
                                    selectedWordLength = 1
                                    onUpdateEditorFromSelection()
                                }
                        }
                    }
                }
                .onChange(of: selectedWordOffset) { _, _ in
                    proxy.scrollTo("orig-\(selectedWordOffset)", anchor: .center)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo("orig-\(selectedWordOffset)", anchor: .center)
                    }
                }
            }

            HStack(spacing: 3) {
                Button(action: onShrinkSelectionRight) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(isEInkEnabled ? paper : Color.blue.opacity(0.1), in: Circle())
                        .overlay { if isEInkEnabled { Circle().strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
                }
                Button(action: onExpandSelectionRight) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(isEInkEnabled ? paper : Color.blue.opacity(0.1), in: Circle())
                        .overlay { if isEInkEnabled { Circle().strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
                }
            }
            .foregroundColor(.blue)
            .einkAccentForeground(.blue)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private var translatedTokensRowView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(translationTokens) { token in
                        let isSelected = (token.originalOffset < selectedWordOffset + selectedWordLength &&
                                          token.originalOffset + token.originalLength > selectedWordOffset)
                        Text(token.translatedText)
                            .font(.subheadline)
                            .bold(isSelected)
                            .underline()
                            .foregroundColor(isSelected ? (isEInkEnabled ? .white : .blue) : .primary)
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                            .background(isSelected ? (isEInkEnabled ? Color.black : Color.blue.opacity(0.1)) : Color.clear)
                            .cornerRadius(4)
                            .id("trans-\(token.id)")
                            .onTapGesture {
                                selectedWordOffset = token.originalOffset
                                selectedWordLength = token.originalLength
                                onUpdateEditorFromSelection()
                            }
                    }
                }
            }
            .onChange(of: selectedWordOffset) { _, _ in
                if let selectedToken = translationTokens.first(where: {
                    $0.originalOffset < selectedWordOffset + selectedWordLength &&
                    $0.originalOffset + $0.originalLength > selectedWordOffset
                }) {
                    proxy.scrollTo("trans-\(selectedToken.id)", anchor: .center)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let selectedToken = translationTokens.first(where: {
                        $0.originalOffset < selectedWordOffset + selectedWordLength &&
                        $0.originalOffset + $0.originalLength > selectedWordOffset
                    }) {
                        proxy.scrollTo("trans-\(selectedToken.id)", anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var customMeaningInputView: some View {
        HStack {
            if isLoadingDefinition { ProgressView().controlSize(.small) }
            TextField("Nhập nghĩa dịch...", text: $customMeaning)
                .textInputAutocapitalization(.never)

            if !customMeaning.isEmpty {
                Button(action: { customMeaning = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private var suggestionChipsView: some View {
        HStack(spacing: 8) {
            Button(action: { showingManageDefinitionsSheet = true }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                    .einkAccentForeground(.blue)
                    .padding(8)
                    .background(isEInkEnabled ? paper : Color.blue.opacity(0.1), in: Circle())
                    .overlay { if isEInkEnabled { Circle().strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
            }

            Button(action: pasteFromClipboard) {
                Image(systemName: "doc.on.clipboard")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                    .einkAccentForeground(.blue)
                    .padding(8)
                    .background(isEInkEnabled ? paper : Color.blue.opacity(0.1), in: Circle())
                    .overlay { if isEInkEnabled { Circle().strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
            }
            .accessibilityLabel("Dán từ clipboard")
            .accessibilityHint("Dán nội dung clipboard vào ô nhập nghĩa")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestionChips) { chip in
                        let bgFill: Color = {
                            if isEInkEnabled {
                                switch chip.category {
                                case .name: return EInkPalette.grayDark
                                case .vietPhrase: return EInkPalette.grayMedium
                                case .hanViet: return EInkPalette.grayLight
                                }
                            }
                            return Color(red: 0.12, green: 0.12, blue: 0.15)
                        }()

                        let textColor: Color = {
                            if isEInkEnabled {
                                switch chip.category {
                                case .name: return EInkPalette.selectedContent
                                case .vietPhrase: return EInkPalette.ink
                                case .hanViet: return EInkPalette.ink
                                }
                            }
                            return chip.category.textColor
                        }()

                        Button(action: { customMeaning = chip.text }) {
                            Text(chip.text)
                                .font(.subheadline)
                                .fontWeight(isEInkEnabled ? .medium : .regular)
                                .foregroundColor(textColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(bgFill)
                                .cornerRadius(15)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 15)
                                        .stroke(
                                            isEInkEnabled ? (chip.category == .hanViet ? EInkPalette.grayDark : EInkPalette.ink) : chip.category.borderColor,
                                            style: (isEInkEnabled && chip.category == .hanViet) ? StrokeStyle(lineWidth: 1, dash: [3, 2]) : StrokeStyle(lineWidth: 1)
                                        )
                                 )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func pasteFromClipboard() {
        guard let pasted = UIPasteboard.general.string,
              !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ToastManager.shared.show(message: "Không có nội dung trong clipboard", type: .info)
            return
        }
        customMeaning = pasted
    }
}
