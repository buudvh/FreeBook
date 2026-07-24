import SwiftUI

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
    let suggestionChips: [String]
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
    let onGetDictionaryMatches: (String) -> [DictionaryMatchInfo]

    var body: some View {
        VStack(spacing: 16) {
            dragIndicatorView
            headerView
            originalSentenceRowView
            translatedTokensRowView
            customMeaningInputView
            suggestionChipsView
            formattingButtonsView
            typeAndScopePickersView
            updateButtonView
            Divider()
            quickLookupLinksView
        }
        .padding()
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
                        self.customMeaning = TranslateUtils.getHanViet(selectedTextForDefinition)
                    }
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
        HStack(spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onExpandSelectionLeft) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
                Button(action: onShrinkSelectionLeft) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .foregroundColor(.blue)

            Spacer()

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

            Spacer()

            HStack(spacing: 12) {
                Button(action: onShrinkSelectionRight) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
                Button(action: onExpandSelectionRight) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .foregroundColor(.blue)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private var translatedTokensRowView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(translationTokens) { token in
                        let isSelected = (token.originalOffset < selectedWordOffset + selectedWordLength &&
                                          token.originalOffset + token.originalLength > selectedWordOffset)
                        Text(token.translatedText)
                            .font(.subheadline)
                            .bold(isSelected)
                            .underline()
                            .foregroundColor(isSelected ? .blue : .primary)
                            .padding(.horizontal, 4)
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
                .autocorrectionDisabled()
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
                    ForEach(suggestionChips, id: \.self) { chip in
                        Button(action: { customMeaning = chip }) {
                            Text(chip)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(15)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formattingButtonsView: some View {
        HStack(spacing: 8) {
            ForEach(["aa", "Aa¹", "Aa²", "Aa", "AA"], id: \.self) { format in
                Button(action: {
                    customMeaning = onFormatMeaning(customMeaning, format)
                }) {
                    Text(format)
                        .font(.body)
                        .fontWeight(.bold)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(8)
                }
            }
        }
    }

    private var typeAndScopePickersView: some View {
        HStack(spacing: 12) {
            Picker("Loại", selection: $saveAsNameType) {
                Text("Names").tag(true)
                Text("VP").tag(false)
            }
            .pickerStyle(.segmented)

            Picker("Phạm vi", selection: $saveToBookSpecific) {
                Text("Riêng").tag(true)
                Text("Chung").tag(false)
            }
            .pickerStyle(.segmented)
        }
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
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
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
