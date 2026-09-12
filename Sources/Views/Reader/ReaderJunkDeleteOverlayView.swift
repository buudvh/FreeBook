import SwiftUI

struct ReaderJunkDeleteOverlayView: View {
    @Binding var isPresented: Bool
    let selectedTheme: ReaderTheme
    let originalSentence: String
    @Binding var selectedWordOffset: Int
    @Binding var selectedWordLength: Int
    let translationTokens: [TranslationWordToken]
    @Binding var junkPatternInput: String

    let onExpandSelectionLeft: () -> Void
    let onShrinkSelectionLeft: () -> Void
    let onShrinkSelectionRight: () -> Void
    let onExpandSelectionRight: () -> Void
    let onUpdateEditorFromSelection: () -> Void
    let onConfirmDelete: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            dragIndicatorView
            headerView
            originalSentenceRowView
            translatedTokensRowView
            junkInputView
            actionButtonsView
        }
        .padding()
        .background(Color(uiColor: .systemBackground).onTapGesture { hideKeyboard() })
    }

    private var dragIndicatorView: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Xoá từ rác")
                    .font(.headline)
                Text("Từ sẽ bị xoá khỏi câu trước khi chuẩn hoá")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: {
                isPresented = false
                onCancel()
            }) {
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
                        .background(Color.red.opacity(0.1))
                        .clipShape(Circle())
                }
                Button(action: onShrinkSelectionLeft) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .foregroundColor(.red)

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
                                .foregroundColor(isSelected ? .red : .primary)
                                .id("junk-orig-\(index)")
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
                        proxy.scrollTo("junk-orig-\(selectedWordOffset)", anchor: .center)
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo("junk-orig-\(selectedWordOffset)", anchor: .center)
                        }
                    }
                }
            }

            HStack(spacing: 3) {
                Button(action: onShrinkSelectionRight) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Circle())
                }
                Button(action: onExpandSelectionRight) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .foregroundColor(.red)
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
                            .foregroundColor(isSelected ? .red : .primary)
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                            .background(isSelected ? Color.red.opacity(0.1) : Color.clear)
                            .cornerRadius(4)
                            .id("junk-trans-\(token.id)")
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
                        proxy.scrollTo("junk-trans-\(selectedToken.id)", anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var junkInputView: some View {
        HStack {
            TextField("Nhập từ muốn xóa...", text: $junkPatternInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.body)

            if !junkPatternInput.isEmpty {
                Button(action: { junkPatternInput = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private var actionButtonsView: some View {
        HStack(spacing: 16) {
            Button(action: {
                isPresented = false
                onCancel()
            }) {
                Text("Hủy")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(10)
            }

            Button(action: {
                let trimmed = junkPatternInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                isPresented = false
                onConfirmDelete(trimmed)
            }) {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Xác nhận")
                        .font(.body)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(junkPatternInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.red)
                .cornerRadius(10)
            }
            .disabled(junkPatternInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.top, 8)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
