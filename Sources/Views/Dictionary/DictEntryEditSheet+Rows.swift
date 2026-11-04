import SwiftUI
import UIKit

/// Các hàng của màn Sửa từ VP/Name, chép hình dạng từ panel Dịch của Reader (`ReaderDefinitionOverlayView` và
/// `+Rows`): hàng từ gốc có hai cặp nút nới/thu, hàng token đã dịch, ô nghĩa, dải chip, nút aa…AA, nút Cập nhật và
/// dải công cụ tra cứu. Reader tô `.white`; ở đây `.primary` cùng độ mờ để theo sáng/tối của Cài đặt.
///
/// Thành viên là `internal` vì `private` của Swift chỉ có hiệu lực trong một file.
extension DictEntryEditSheet {

    // MARK: - Header

    var dictBadgeText: String {
        let typeLabel = dictType == .names ? "Name" : "VP"
        let scopeLabel = scopeBookId == nil ? "Chung" : "Riêng truyện"
        return "\(typeLabel) · \(scopeLabel)"
    }

    /// Badge loại · phạm vi (chỉ đọc) + nút bút chì gõ lại từ gốc. Một `ToolbarItem` để iOS không tự giãn cách.
    var headerTrailingView: some View {
        HStack(spacing: 6) {
            Text(dictBadgeText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15), in: Capsule())
                .accessibilityLabel("Từ điển \(dictType.displayName), \(scopeBookId == nil ? "chung" : "riêng của truyện")")

            Button(action: toggleKeyEditing) {
                Image(systemName: isEditingKey ? "pencil.circle.fill" : "pencil")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(isEditingKey ? "Ẩn ô sửa từ gốc" : "Sửa từ gốc")
        }
    }

    func toggleKeyEditing() {
        isEditingKey.toggle()
        guard isEditingKey else {
            isKeyFieldFocused = false
            return
        }
        // Ô nhập vừa được chèn vào cây view ở lượt vẽ này — đặt focus ở lượt sau.
        DispatchQueue.main.async { isKeyFieldFocused = true }
    }

    // MARK: - Ô gõ lại từ gốc

    var keyFieldView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField("Từ gốc (key)", text: $workingKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isKeyFieldFocused)

                if displayKey != trimmedOriginalKey {
                    Button(action: { workingKey = originalKey }) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Trả lại từ gốc ban đầu")
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            Text("Nếu thay đổi từ gốc thành từ khác đã tồn tại, nghĩa của từ đó sẽ bị ghi đè.")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Hàng từ gốc

    var originalKeyRowView: some View {
        HStack(spacing: 4) {
            HStack(spacing: 3) {
                selectionChevron("chevron.left", label: "Mở rộng sang trái", action: expandSelectionLeft)
                selectionChevron("chevron.right", label: "Thu hẹp bên trái", action: shrinkSelectionLeft)
            }

            originalCharactersView

            HStack(spacing: 3) {
                selectionChevron("chevron.left", label: "Thu hẹp bên phải", action: shrinkSelectionRight)
                selectionChevron("chevron.right", label: "Mở rộng sang phải", action: expandSelectionRight)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    func selectionChevron(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.12))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Từng đơn vị UTF-16 của từ gốc (như Reader duyệt `NSString` của câu gốc); chạm một chữ = chọn đúng chữ đó.
    var originalCharactersView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    let nsKey = displayKey as NSString
                    ForEach(0..<nsKey.length, id: \.self) { index in
                        let char = nsKey.substring(with: NSRange(location: index, length: 1))
                        let isSelected = index >= selectionOffset && index < selectionOffset + selectionLength
                        Text(char)
                            .font(.body)
                            .bold(isSelected)
                            .underline(isSelected)
                            .foregroundColor(isSelected ? .primary : Color.primary.opacity(0.45))
                            .id("orig-\(index)")
                            .onTapGesture { select(offset: index, length: 1) }
                    }
                }
            }
            .onChange(of: selectionOffset) { _, _ in
                withAnimation { proxy.scrollTo("orig-\(selectionOffset)", anchor: .center) }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation { proxy.scrollTo("orig-\(selectionOffset)", anchor: .center) }
                }
            }
        }
    }

    // MARK: - Hàng token đã dịch

    func tokenOverlapsSelection(_ token: TranslationWordToken) -> Bool {
        token.originalOffset < selectionOffset + selectionLength
            && token.originalOffset + token.originalLength > selectionOffset
    }

    var translatedTokensRowView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(tokens) { token in
                        let isSelected = tokenOverlapsSelection(token)
                        Text(token.translatedText)
                            .font(.subheadline)
                            .bold(isSelected)
                            .underline()
                            .foregroundColor(isSelected ? .primary : Color.primary.opacity(0.45))
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                            .background(isSelected ? Color.primary.opacity(0.15) : Color.clear)
                            .cornerRadius(4)
                            .id("trans-\(token.id)")
                            .onTapGesture { select(offset: token.originalOffset, length: token.originalLength) }
                    }
                }
            }
            .onChange(of: selectionOffset) { _, _ in scrollToSelectedToken(proxy: proxy) }
            .onChange(of: tokens.map(\.id)) { _, _ in scrollToSelectedToken(proxy: proxy) }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { scrollToSelectedToken(proxy: proxy) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
        .padding(.horizontal, 4)
    }

    func scrollToSelectedToken(proxy: ScrollViewProxy) {
        guard let token = tokens.first(where: { tokenOverlapsSelection($0) }) else { return }
        withAnimation { proxy.scrollTo("trans-\(token.id)", anchor: .center) }
    }

    // MARK: - Ô nghĩa

    var meaningInputView: some View {
        HStack(alignment: .top) {
            if isLoadingMeaning { ProgressView().controlSize(.small) }
            TextField("Nhập nghĩa dịch...", text: meaningBinding, axis: .vertical)
                .lineLimit(2, reservesSpace: true)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(false)

            if !meaning.isEmpty {
                Button(action: { editMeaning("") }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Xoá nghĩa")
                .padding(.top, 2)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 56)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Dải chip nghĩa

    /// Màn quản lý nghĩa (⚙) cần một truyện cho hai nhóm "(Riêng)" ⇒ không có truyện thì ẩn nút.
    var manageBookId: String? {
        guard let chipBookId, !chipBookId.isEmpty else { return nil }
        return chipBookId
    }

    var suggestionChipsView: some View {
        HStack(spacing: 8) {
            if manageBookId != nil {
                Button(action: openManageDefinitions) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .padding(8)
                        .background(Color.primary.opacity(0.12))
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                }
                .accessibilityLabel("Quản lý nghĩa từ")
            }

            Button(action: pasteFromClipboard) {
                AppGlyph.paste.image(size: 17)
                    .foregroundColor(.primary)
                    .padding(8)
                    .background(Color.primary.opacity(0.12))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
            }
            .accessibilityLabel("Dán từ clipboard")
            .accessibilityHint("Dán nội dung clipboard vào ô nhập nghĩa")

            // Badge R/C nhô lên trên phải chip — padding âm như panel Dịch để hàng vẫn cao 36.
            MeaningSuggestionChipRow(chips: chips) { editMeaning($0.text) }
                .padding(.top, -ChipCornerBadge.inset)
        }
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
    }

    func pasteFromClipboard() {
        guard let pasted = UIPasteboard.general.string,
              !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ToastManager.shared.show(message: "Không có nội dung trong clipboard", type: .info)
            return
        }
        editMeaning(pasted.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: ""))
    }

    /// Tra lại `matches` ngay lúc mở (đồng bộ, vài lượt `findLongestMatch`): màn quản lý ghi nghĩa theo đúng từ và
    /// danh sách nó nhận, nên không được dùng kết quả của vùng chọn trước còn đang tra dở.
    func openManageDefinitions() {
        guard let book = manageBookId else { return }
        let word = saveTargetKey
        guard !word.isEmpty else { return }
        manageWord = word
        dictionaryMatches = ReaderView.dictionaryMatches(for: word, bookId: book)
        showingManageDefinitions = true
    }

    var manageDefinitionsSheet: some View {
        ManageDefinitionsView(
            word: manageWord,
            bookId: manageBookId ?? "",
            matches: $dictionaryMatches,
            onChanged: definitionsDidChange
        )
    }

    /// Màn ⚙ đã ghi đĩa: tra lại chip/token, báo danh sách nạp lại. Ô nghĩa giữ nguyên chữ đang có.
    func definitionsDidChange() {
        refreshSelectionData(needsMeaning: false)
        refreshTokens()
        onDefinitionsChanged()
    }

    // MARK: - aa…AA, thông báo, Cập nhật

    var caseButtonsView: some View {
        HStack {
            TextCaseButtonGroup(isDisabled: meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { style in
                editMeaning(TextCaseFormatter.format(meaning, style: style))
            }
            Spacer(minLength: 0)
        }
    }

    /// "Lưu thêm X, giữ nguyên Y" khi vùng chọn là một phần; cảnh báo ghi đè khi từ đích đã có trong danh sách.
    @ViewBuilder
    var noticeView: some View {
        if let newKey = addedKey {
            noticeLine("Lưu thêm \(newKey), giữ nguyên \(trimmedOriginalKey)", systemImage: "plus.circle", color: .secondary)
        }
        if let action = saveAction, action != .update, targetExistingValue != nil {
            noticeLine("\(saveTargetKey) đã có trong danh sách — nghĩa cũ sẽ bị ghi đè.",
                       systemImage: "exclamationmark.triangle.fill", color: .orange)
        }
    }

    /// Cụm sẽ được thêm thành mục mới (vùng chọn là một phần); `nil` ở hai cách lưu còn lại.
    var addedKey: String? {
        guard case .addNew(let newKey)? = saveAction else { return nil }
        return newKey
    }

    func noticeLine(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundColor(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var updateButtonView: some View {
        Button(action: handleSave) {
            Label("Cập nhật", systemImage: "tray.and.arrow.down.fill")
        }
        .buttonStyle(.appFilled)
        .disabled(isSaveDisabled)
    }

    // MARK: - Tra cứu nhanh

    var quickLookupLinksView: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(searchEngines) { engine in
                        Button(action: { performQuickLookup(engine) }) {
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

            Button(action: { showingSearchEngineConfig = true }) {
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

    /// Tra cụm đang chọn (chữ gốc) — cùng luật dựng URL với Reader, mở trình duyệt trong cover gắn trong sheet này.
    func performQuickLookup(_ engine: SearchEngine) {
        guard let url = DictEntryEditLookup.lookupURLString(engine: engine, query: saveTargetKey) else { return }
        lookupRoute = ReaderLookupRoute(urlString: url)
    }
}
