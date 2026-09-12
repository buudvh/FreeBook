import SwiftUI

/// Panel **Copy nội dung gốc**: chọn lại cụm chữ trên text **gốc** rồi copy đúng cụm đó.
///
/// Vì sao không copy thẳng từ vùng bôi đen như nút Copy: khi bật dịch, vùng bôi đen nằm trên **bản
/// dịch**, phải map về gốc bằng `ReaderSelectionMapper` — và map có thể lệch khi `translationSpans`
/// rỗng (vùng vừa bị rule rewrite). Cho người dùng thấy từng ký tự gốc và tự nới/thu là cách duy nhất
/// bảo đảm copy đúng chữ họ muốn.
///
/// Không có nút Hủy: **mọi** đường đóng đều copy (chốt của chủ dự án). Host gom về đúng một hàm
/// `commitCopyOriginal()` nên nút ✕ ở đây cũng gọi `onCommit`.
struct ReaderCopyOriginalOverlayView: View {
    let originalSentence: String
    @Binding var selectedWordOffset: Int
    @Binding var selectedWordLength: Int
    let translationTokens: [TranslationWordToken]

    let onExpandSelectionLeft: () -> Void
    let onShrinkSelectionLeft: () -> Void
    let onShrinkSelectionRight: () -> Void
    let onExpandSelectionRight: () -> Void
    let onUpdateEditorFromSelection: () -> Void
    /// Copy chuỗi đang chọn vào clipboard rồi đóng panel.
    let onCommit: () -> Void

    private var accent: Color { Color(red: 0.20, green: 0.72, blue: 0.55) }

    private var selectedOriginal: String {
        let ns = originalSentence as NSString
        let range = NSRange(location: selectedWordOffset, length: selectedWordLength)
        guard selectedWordOffset >= 0, selectedWordLength > 0, NSMaxRange(range) <= ns.length else {
            return ""
        }
        return ns.substring(with: range)
    }

    var body: some View {
        VStack(spacing: 14) {
            dragIndicatorView
            headerView
            originalSentenceRowView
            translatedTokensRowView
            previewView
            copyButtonView
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
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
                Text("Copy nội dung gốc")
                    .font(.headline)
                Text("Chọn lại cụm chữ gốc; đóng panel là copy")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onCommit) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title2)
            }
            .accessibilityLabel("Copy rồi đóng")
        }
    }

    private var originalSentenceRowView: some View {
        HStack(spacing: 4) {
            HStack(spacing: 3) {
                chevronButton("chevron.left", action: onExpandSelectionLeft)
                chevronButton("chevron.right", action: onShrinkSelectionLeft)
            }
            .foregroundColor(accent)

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
                                .foregroundColor(isSelected ? accent : .primary)
                                .id("copy-orig-\(index)")
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
                        proxy.scrollTo("copy-orig-\(selectedWordOffset)", anchor: .center)
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo("copy-orig-\(selectedWordOffset)", anchor: .center)
                        }
                    }
                }
            }

            HStack(spacing: 3) {
                chevronButton("chevron.left", action: onShrinkSelectionRight)
                chevronButton("chevron.right", action: onExpandSelectionRight)
            }
            .foregroundColor(accent)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private func chevronButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.12))
                .clipShape(Circle())
        }
    }

    private var translatedTokensRowView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(translationTokens) { token in
                    let isSelected = (token.originalOffset < selectedWordOffset + selectedWordLength &&
                                      token.originalOffset + token.originalLength > selectedWordOffset)
                    Text(token.translatedText)
                        .font(.subheadline)
                        .bold(isSelected)
                        .underline()
                        .foregroundColor(isSelected ? accent : .primary)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                        .background(isSelected ? accent.opacity(0.12) : Color.clear)
                        .cornerRadius(4)
                        .onTapGesture {
                            selectedWordOffset = token.originalOffset
                            selectedWordLength = token.originalLength
                            onUpdateEditorFromSelection()
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var previewView: some View {
        HStack {
            Text(selectedOriginal.isEmpty ? "Chưa chọn chữ nào" : selectedOriginal)
                .font(.body)
                .foregroundColor(selectedOriginal.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(selectedWordLength) ký tự")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private var copyButtonView: some View {
        Button(action: onCommit) {
            HStack {
                Image(systemName: "doc.on.clipboard")
                Text("Copy")
                    .font(.body)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selectedOriginal.isEmpty ? Color.gray : accent)
            .cornerRadius(10)
        }
        .disabled(selectedOriginal.isEmpty)
    }
}
