import SwiftUI

/// Sheet thêm / sửa **một từ** của token tùy chọn (1.3.1063): ô "Chữ gốc" + ô "Nghĩa", nút "Lưu" chữ ở header, không nút
/// chỉ để đóng (vuốt xuống; gõ dở thì `confirmDiscardOnSwipe` hỏi lại). Chỗ trình bày bọc `Group { … }.appGlassSheet()`.
///
/// Luật lấy từ `QuickTranslationCustomTokenStore` (`keyError` / `meaningError` — cùng luật với nhập file), hiện ngay dưới
/// ô; ô còn trống thì không tô đỏ. Ghi do màn danh sách làm (`onSave` trả chuỗi lỗi nếu không lưu được).
struct QuickTranslationCustomTokenEntryEditorSheet: View {
    typealias Entry = QuickTranslationCustomToken.Entry

    private enum Field: Hashable {
        case key
        case meaning
    }

    let tokenName: String
    /// `nil` = thêm từ mới.
    let original: Entry?
    let onSave: (_ key: String, _ meaning: String) -> String?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var key: String
    @State private var meaning: String
    @State private var saveError: String?

    init(tokenName: String, original: Entry?, onSave: @escaping (_ key: String, _ meaning: String) -> String?) {
        self.tokenName = tokenName
        self.original = original
        self.onSave = onSave
        _key = State(initialValue: original?.key ?? "")
        _meaning = State(initialValue: original?.meaning ?? "")
    }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedMeaning: String { meaning.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var keyError: String? {
        QuickTranslationCustomTokenStore.shared.keyError(trimmedKey, in: tokenName, replacing: original?.key)
    }

    private var meaningError: String? {
        QuickTranslationCustomTokenStore.shared.meaningError(trimmedMeaning)
    }

    private var isDirty: Bool {
        trimmedKey != (original?.key ?? "") || trimmedMeaning != (original?.meaning ?? "")
    }

    private var canSave: Bool { isDirty && keyError == nil && meaningError == nil }

    var body: some View {
        NavigationStack {
            Form { Group {
                Section {
                    TextField("红色", text: $key)
                        .font(.title3)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .key)
                    if !trimmedKey.isEmpty, let keyError {
                        errorText(keyError)
                    }
                } header: {
                    Text("Chữ gốc")
                }

                Section {
                    TextField("màu đỏ", text: $meaning)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .meaning)
                    if !trimmedMeaning.isEmpty, let meaningError {
                        errorText(meaningError)
                    }
                    if let saveError {
                        errorText(saveError)
                    }
                } header: {
                    Text("Nghĩa")
                }
            }.glassSheetRows() }
            .pageTitle(original == nil ? "Thêm từ" : "Sửa từ")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }
                        .headerTextButton()
                        .disabled(!canSave)
                }
            }
            .onChange(of: key) { _, _ in saveError = nil }
            .onChange(of: meaning) { _, _ in saveError = nil }
            .onAppear {
                focusedField = original == nil ? .key : .meaning
            }
        }
        .confirmDiscardOnSwipe(isDirty: isDirty)
        .presentationDragIndicator(.visible)
    }

    private func errorText(_ message: String) -> some View {
        Text(verbatim: message)
            .font(.footnote)
            .foregroundColor(.red)
    }

    private func save() {
        guard canSave else { return }
        if let error = onSave(trimmedKey, trimmedMeaning) {
            saveError = error
            return
        }
        dismiss()
    }
}
