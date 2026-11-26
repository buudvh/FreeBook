import SwiftUI

/// Sheet **Thêm token** / **Sửa token** của token tùy chọn `<@tên>` (1.3.1063): ô "Tên token" (kèm cú pháp `<@tên>` xem
/// trước ở cuối ô) + ô "Mô tả", nút "Lưu" chữ ở header, không nút chỉ để đóng (vuốt xuống; gõ dở thì
/// `confirmDiscardOnSwipe` hỏi lại). Chỗ trình bày bọc `Group { … }.appGlassSheet()`.
///
/// - Sửa: tên **khoá** (rule gọi token bằng tên — đổi tên là rule cũ thôi khớp), chỉ đổi mô tả.
/// - Luật tên lấy từ `QuickTranslationCustomTokenStore.nameError` (cùng luật parser rule), hiện ngay dưới ô.
/// - Sheet tự ghi qua store rồi toast (mở được từ ba chỗ: màn Token tùy chọn, màn danh sách từ, bảng token của màn sửa
///   rule); `onSaved(tên)` để chỗ mở đọc lại.
struct QuickTranslationCustomTokenEditorSheet: View {
    typealias Store = QuickTranslationCustomTokenStore

    private enum Field: Hashable {
        case name
        case title
    }

    /// `nil` = thêm token mới.
    let original: QuickTranslationCustomToken?
    let onSaved: (_ name: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var name: String
    @State private var title: String
    @State private var saveError: String?

    init(original: QuickTranslationCustomToken?, onSaved: @escaping (_ name: String) -> Void = { _ in }) {
        self.original = original
        self.onSaved = onSaved
        _name = State(initialValue: original?.name ?? "")
        _title = State(initialValue: original?.title ?? "")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var nameError: String? {
        original == nil ? Store.shared.nameError(trimmedName) : nil
    }

    private var isDirty: Bool {
        trimmedName != (original?.name ?? "") || trimmedTitle != (original?.title ?? "")
    }

    private var canSave: Bool { isDirty && nameError == nil }

    var body: some View {
        NavigationStack {
            Form { Group {
                Section {
                    HStack(spacing: 8) {
                        TextField("mau", text: $name)
                            .font(.title3)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .disabled(original != nil)
                            .foregroundColor(original != nil ? .secondary : .primary)
                            .focused($focusedField, equals: .name)
                        if !trimmedName.isEmpty {
                            Text(verbatim: "<@\(trimmedName)>")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.accentColor)
                                .lineLimit(1)
                        }
                    }
                    if !trimmedName.isEmpty, let nameError {
                        errorText(nameError)
                    }
                } header: {
                    SectionHelpHeader("Tên token", texts: [
                        Text(verbatim: "Chữ thường không dấu a-z, số 0-9, gạch dưới _; bắt đầu bằng chữ; tối đa \(QuickTranslationCustomTokenListParser.maxNameLength) ký tự."),
                        Text(verbatim: "Không đổi được sau khi tạo, vì rule gọi token bằng tên này.")
                    ])
                }

                Section {
                    TextField("Màu sắc", text: $title)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .title)
                    if let saveError {
                        errorText(saveError)
                    }
                } header: {
                    Text("Mô tả")
                }
            }.glassSheetRows() }
            .pageTitle(original == nil ? "Thêm token" : "Sửa token")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }
                        .headerTextButton()
                        .disabled(!canSave)
                }
            }
            .onChange(of: name) { _, _ in saveError = nil }
            .onChange(of: title) { _, _ in saveError = nil }
            .onAppear {
                focusedField = original == nil ? .name : .title
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
        let error: String?
        if let original {
            error = Store.shared.updateTitle(trimmedTitle, of: original.name)
        } else {
            error = Store.shared.createToken(name: trimmedName, title: trimmedTitle)
        }
        if let error {
            saveError = error
            return
        }
        let syntax = "<@\(trimmedName)>"
        ToastManager.shared.show(message: original == nil ? "Đã thêm token \(syntax)" : "Đã lưu token \(syntax)", type: .success)
        onSaved(trimmedName)
        dismiss()
    }
}
