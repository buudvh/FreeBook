import SwiftUI

/// Sheet thêm/sửa **một** cặp của Bộ ngoặc (1.3.692): hai ô Ngoặc mở / Ngoặc đóng (mỗi ô một ký tự, chữ lớn canh
/// giữa) và ô Tên không bắt buộc.
///
/// - Kiểu sheet 1.3.641: không nút đóng, vuốt xuống để đóng; có nội dung chưa lưu thì `confirmDiscardOnSwipe` hỏi lại.
///   Nút "Lưu" chữ bên phải.
/// - Lỗi lấy từ `QuickTranslationRuleBracketStore.validationError` (một chỗ quyết định luật), hiện ngay dưới hai ô;
///   có lỗi thì không lưu được. Sheet mới tinh chưa gõ gì thì không tô đỏ "Chưa nhập…".
/// - Ghi do màn danh sách làm (`onSave`): nó kiểm lại trên danh sách đọc mới từ store rồi mới ghi, trả chuỗi lỗi nếu
///   không lưu được — sheet giữ nguyên để sửa tiếp.
struct QuickTranslationRuleBracketEditorSheet: View {
    typealias Pair = QuickTranslationRuleBracketPair

    private enum Field: Hashable {
        case open
        case close
        case name
    }

    /// `nil` = thêm cặp mới.
    let original: Pair?
    /// Danh sách đang hiện, chỉ để báo lỗi ngay lúc gõ.
    let existingPairs: [Pair]
    /// Vị trí của cặp đang sửa trong `existingPairs` — bỏ qua khi so trùng ký tự.
    let editingIndex: Int?
    let onSave: (Pair) -> String?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var open: String
    @State private var close: String
    @State private var name: String
    /// Lỗi do màn danh sách trả về lúc ghi; xoá khi người dùng sửa tiếp.
    @State private var saveError: String?

    init(
        original: Pair?,
        existingPairs: [Pair],
        editingIndex: Int?,
        onSave: @escaping (Pair) -> String?
    ) {
        self.original = original
        self.existingPairs = existingPairs
        self.editingIndex = editingIndex
        self.onSave = onSave
        _open = State(initialValue: original?.open ?? "")
        _close = State(initialValue: original?.close ?? "")
        _name = State(initialValue: original?.name ?? "")
    }

    private var trimmedOpen: String { open.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedClose: String { close.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var validationError: String? {
        QuickTranslationRuleBracketStore.validationError(
            open: trimmedOpen,
            close: trimmedClose,
            in: existingPairs,
            excludingIndex: editingIndex
        )
    }

    private var shownError: String? {
        if let saveError { return saveError }
        if trimmedOpen.isEmpty && trimmedClose.isEmpty { return nil }
        return validationError
    }

    private var isDirty: Bool {
        trimmedOpen != (original?.open ?? "")
            || trimmedClose != (original?.close ?? "")
            || trimmedName != (original?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form { Group {
                Section {
                    HStack(spacing: 12) {
                        glyphField("Ngoặc mở", placeholder: "(", text: $open, field: .open)
                        glyphField("Ngoặc đóng", placeholder: ")", text: $close, field: .close)
                    }
                    .padding(.vertical, 4)

                    if let shownError {
                        Text(verbatim: shownError)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Cặp ngoặc")
                }

                Section {
                    TextField("Không bắt buộc, vd Ngoặc vuông toàn khổ", text: $name)
                        .focused($focusedField, equals: .name)
                } header: {
                    Text("Tên")
                }
            }.glassSheetRows() }
            .pageTitle(original == nil ? "Thêm cặp ngoặc" : "Sửa cặp ngoặc")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }
                        .headerTextButton()
                        .disabled(validationError != nil || !isDirty)
                }
            }
            .onChange(of: open) { old, new in
                normalize(old: old, new: new, field: .open)
            }
            .onChange(of: close) { old, new in
                normalize(old: old, new: new, field: .close)
            }
            .onChange(of: name) { _, _ in
                saveError = nil
            }
            .onAppear {
                if original == nil {
                    focusedField = .open
                }
            }
        }
        .confirmDiscardOnSwipe(isDirty: isDirty)
        .presentationDragIndicator(.visible)
    }

    private func glyphField(
        _ title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            TextField(placeholder, text: text)
                .font(.system(size: 34))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: field)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity)
    }

    /// Mỗi ô giữ đúng một ký tự: gõ thêm ⇒ giữ ký tự vừa gõ (thay ký tự cũ). Dán cả cặp (vd "【】") vào ô mở đang
    /// trống khi ô đóng cũng trống ⇒ chia sang hai ô. Gõ xong ô mở thì con trỏ sang ô đóng.
    ///
    /// Gán lại `open`/`close` ở đây làm `onChange` chạy thêm một lượt với chuỗi một ký tự ⇒ rơi vào nhánh `guard`
    /// và dừng, không lặp.
    private func normalize(old: String, new: String, field: Field) {
        saveError = nil
        let chars = Array(new)
        guard chars.count > 1 else {
            if field == .open, chars.count == 1, trimmedClose.isEmpty {
                focusedField = .close
            }
            return
        }
        if field == .open, old.isEmpty, chars.count == 2, close.isEmpty {
            open = String(chars[0])
            close = String(chars[1])
            focusedField = .name
            return
        }
        let typed = chars.last(where: { String($0) != old }) ?? chars[chars.count - 1]
        if field == .open {
            open = String(typed)
        } else {
            close = String(typed)
        }
    }

    private func save() {
        guard validationError == nil else { return }
        let pair = Pair(
            open: trimmedOpen,
            close: trimmedClose,
            name: trimmedName,
            isEnabled: original?.isEnabled ?? true
        )
        if let error = onSave(pair) {
            saveError = error
            return
        }
        dismiss()
    }
}
