import SwiftUI

public enum SuggestionChipCategory: String, Sendable {
    case name       // Từ điển Names -> Chữ trắng, viền đỏ nhạt
    case vietPhrase // Từ điển VietPhrase -> Chữ trắng, viền xanh nhạt
    case hanViet    // Phiên âm Hán Việt -> Giữ nguyên (chữ xám sáng, viền xám mờ)

    public var borderColor: Color {
        switch self {
        case .name: return Color.red.opacity(0.55)
        case .vietPhrase: return Color(red: 0.45, green: 0.75, blue: 1.0).opacity(0.6)
        case .hanViet: return Color.gray.opacity(0.45)
        }
    }

    public var textColor: Color {
        switch self {
        case .name: return Color.white
        case .vietPhrase: return Color.white
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
    let onRuleAction: (QuickTranslationRuleTrace, ReaderRuleAction) -> Void
    let onAddRule: () -> Void

    /// `@State` phải khai trong struct chính: extension không thêm được stored property.
    @State internal var ruleActionTarget: QuickTranslationRuleTrace? = nil
    @State internal var showingRuleActions = false

    var body: some View {
        VStack(spacing: 8) {
            // Gom thành hai `Group`: thân này đã có đúng 10 con trước 1.3.334, thêm hai hàng nữa là
            // vượt trần `@ViewBuilder` và lỗi "extra argument in call".
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
        .background(Color(uiColor: .systemBackground).onTapGesture { hideKeyboard() })
        .presentationDetents([.height(660), .large])
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
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                }
                Button(action: onShrinkSelectionLeft) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                }
            }
            .foregroundColor(.white)

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
                                .underline(isSelected)
                                .foregroundColor(isSelected ? .white : Color.white.opacity(0.45))
                                .padding(.horizontal, inRuleSpan ? 1 : 0)
                                .background(inRuleSpan ? Color.green.opacity(0.22) : Color.clear)
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
                    withAnimation {
                        proxy.scrollTo("orig-\(selectedWordOffset)", anchor: .center)
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo("orig-\(selectedWordOffset)", anchor: .center)
                        }
                    }
                }
            }

            HStack(spacing: 3) {
                Button(action: onShrinkSelectionRight) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                }
                Button(action: onExpandSelectionRight) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                }
            }
            .foregroundColor(.white)
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
                            .foregroundColor(isSelected ? .white : .primary)
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                            .background(isSelected ? Color.white.opacity(0.15) : Color.clear)
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
                scrollToSelectedToken(proxy: proxy, animated: true)
            }
            .onChange(of: translationTokens.count) { _, _ in
                scrollToSelectedToken(proxy: proxy, animated: true)
            }
            .onChange(of: translationTokens.map(\.id)) { _, _ in
                scrollToSelectedToken(proxy: proxy, animated: true)
            }
            .onAppear {
                scrollToSelectedToken(proxy: proxy, animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    scrollToSelectedToken(proxy: proxy, animated: true)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    scrollToSelectedToken(proxy: proxy, animated: true)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func scrollToSelectedToken(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let selectedToken = translationTokens.first(where: {
            $0.originalOffset < selectedWordOffset + selectedWordLength &&
            $0.originalOffset + $0.originalLength > selectedWordOffset
        }) else { return }

        if animated {
            withAnimation {
                proxy.scrollTo("trans-\(selectedToken.id)", anchor: .center)
            }
        } else {
            proxy.scrollTo("trans-\(selectedToken.id)", anchor: .center)
        }
    }

    private var customMeaningInputView: some View {
        HStack(alignment: .top) {
            if isLoadingDefinition { ProgressView().controlSize(.small) }
            TextField("Nhập nghĩa dịch...", text: $customMeaning, axis: .vertical)
                .lineLimit(2, reservesSpace: true)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(false)
                .onChange(of: customMeaning) { _, newValue in
                    if newValue.contains("\n") || newValue.contains("\r") {
                        customMeaning = newValue.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
                    }
                }

            if !customMeaning.isEmpty {
                Button(action: { customMeaning = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 56)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private var suggestionChipsView: some View {
        HStack(spacing: 8) {
            Button(action: { showingManageDefinitionsSheet = true }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            }

            Button(action: pasteFromClipboard) {
                Image(systemName: "doc.on.clipboard")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            }
            .accessibilityLabel("Dán từ clipboard")
            .accessibilityHint("Dán nội dung clipboard vào ô nhập nghĩa")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestionChips) { chip in
                        Button(action: { customMeaning = chip.text }) {
                            Text(chip.text)
                                .font(.subheadline)
                                .foregroundColor(chip.category.textColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(red: 0.12, green: 0.12, blue: 0.15))
                                .cornerRadius(15)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 15)
                                        .stroke(chip.category.borderColor, lineWidth: 1)
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
        customMeaning = pasted.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
    }
}
