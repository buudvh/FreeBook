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

    var body: some View {
        VStack(spacing: 8) {
            dragIndicatorView
            headerView
            originalSentenceRowView
            translatedTokensRowView
            customMeaningInputView
            suggestionChipsView
            combinedFormattingAndPickersView
            updateButtonView
            Divider()
            quickLookupLinksView
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(Color(uiColor: .systemBackground).onTapGesture { hideKeyboard() })
        .presentationDetents([.height(530), .large])
        .sheet(isPresented: $showingManageDefinitionsSheet) {
            ManageDefinitionsView(
                word: selectedTextForDefinition,
                bookId: bookId,
                matches: $dictionaryMatches,
                onChanged: {
                    self.dictionaryMatches = onGetDictionaryMatches(selectedTextForDefinition)
                    if self.translationMode == "VP" {
                        self.customMeaning = TranslateUtils.translateMeta(selectedTextForDefinition, bookId: bookId)
                    } else {
                        self.customMeaning = onGetHanViet(selectedTextForDefinition)
                    }
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
        HStack(spacing: 4) {
            HStack(spacing: 3) {
                Button(action: onExpandSelectionLeft) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
                Button(action: onShrinkSelectionLeft) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .foregroundColor(.blue)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        let nsSentence = originalSentence as NSString
                        ForEach(0..<nsSentence.length, id: \.self) { index in
                            let char = nsSentence.substring(with: NSRange(location: index, length: 1))
                            let isSelected = (index >= selectedWordOffset && index < selectedWordOffset + selectedWordLength)
                            Text(char)
                                .font(.body)
                                .bold(isSelected)
                                .underline(isSelected)
                                .foregroundColor(isSelected ? .blue : .primary)
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
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
                Button(action: onExpandSelectionRight) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .foregroundColor(.blue)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
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
                            .foregroundColor(isSelected ? .blue : .primary)
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
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
                    withAnimation {
                        proxy.scrollTo("trans-\(selectedToken.id)", anchor: .center)
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let selectedToken = translationTokens.first(where: {
                        $0.originalOffset < selectedWordOffset + selectedWordLength &&
                        $0.originalOffset + $0.originalLength > selectedWordOffset
                    }) {
                        withAnimation {
                            proxy.scrollTo("trans-\(selectedToken.id)", anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var customMeaningInputView: some View {
        HStack {
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
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())
            }

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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var combinedFormattingAndPickersView: some View {
        HStack(spacing: 8) {
            // Cụm 1: Định dạng chữ (aa, Aa¹, Aa², Aa, AA)
            HStack(spacing: 2) {
                ForEach(["aa", "Aa¹", "Aa²", "Aa", "AA"], id: \.self) { format in
                    Button(action: {
                        customMeaning = onFormatMeaning(customMeaning, format)
                    }) {
                        Text(format)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(6)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 20)

            // Cụm 2: Phân loại & Phạm vi Từ điển
            HStack(spacing: 6) {
                // Loại (Names vs VP)
                HStack(spacing: 0) {
                    dictSegmentButton(title: "Names", isSelected: saveAsNameType == true, isPinned: pinnedSaveAsNameType == true) {
                        saveAsNameType = true
                    } onPin: {
                        onPinNameType(true)
                    }

                    Divider()
                        .frame(height: 14)

                    dictSegmentButton(title: "VP", isSelected: saveAsNameType == false, isPinned: pinnedSaveAsNameType == false) {
                        saveAsNameType = false
                    } onPin: {
                        onPinNameType(false)
                    }
                }
                .padding(2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(6)

                // Phạm vi (Riêng vs Chung)
                HStack(spacing: 0) {
                    dictSegmentButton(title: "Riêng", isSelected: saveToBookSpecific == true, isPinned: pinnedSaveToBookSpecific == true) {
                        saveToBookSpecific = true
                    } onPin: {
                        onPinScope(true)
                    }

                    Divider()
                        .frame(height: 14)

                    dictSegmentButton(title: "Chung", isSelected: saveToBookSpecific == false, isPinned: pinnedSaveToBookSpecific == false) {
                        saveToBookSpecific = false
                    } onPin: {
                        onPinScope(false)
                    }
                }
                .padding(2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(6)
            }
        }
    }

    @ViewBuilder
    private func dictSegmentButton(
        title: String,
        isSelected: Bool,
        isPinned: Bool,
        onTap: @escaping () -> Void,
        onPin: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(selectedTheme == .dark ? Color(red: 1.0, green: 0.8, blue: 0.3) : Color.orange)
                }
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
            }
            .foregroundColor(isSelected ? selectedTheme.textColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected ? Color.secondary.opacity(0.25) : Color.clear)
            .cornerRadius(6)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onPin()
            }
        )
    }

    private var updateButtonView: some View {
        Button(action: onSaveDefinition) {
            HStack {
                Spacer()
                Label("Cập nhật", systemImage: "tray.and.arrow.down.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(customMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var quickLookupLinksView: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(searchEngines) { engine in
                        Button(action: {
                            onPerformQuickLookup(engine)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "safari")
                                Text(engine.name)
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(6)
                        }
                    }
                }
            }

            Button(action: onOpenSearchEngineConfig) {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(8)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(6)
            }
            .accessibilityLabel("Cấu hình công cụ tra cứu")
            .accessibilityHint("Nhấn hai lần để quản lý danh sách công cụ tìm kiếm")
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
