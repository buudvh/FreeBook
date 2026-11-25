import SwiftUI

/// Sheet thêm / sửa **một** họ của màn Danh sách họ (1.3.1062): ô "Họ (chữ Hán)" + ô "Âm Hán-Việt", nút "Lưu" chữ ở
/// header, không nút chỉ để đóng (vuốt xuống; gõ dở thì `confirmDiscardOnSwipe` hỏi lại). Chỗ trình bày bọc
/// `Group { … }.appGlassSheet()`.
///
/// - Luật lấy từ `QuickTranslationSurnameStore` (`keyError` / `readingError` — cùng luật với nhập file), hiện ngay dưới
///   ô; ô còn trống thì không tô đỏ. Sửa chữ Hán của một họ = xoá khoá cũ + thêm khoá mới (store lo).
/// - Ghi do màn danh sách làm (`onSave` trả chuỗi lỗi nếu không lưu được — sheet giữ nguyên để sửa tiếp).
/// - Họ gốc đã đổi âm có thêm hàng "Về âm gốc: …".
struct QuickTranslationSurnameEditorSheet: View {
    typealias Entry = QuickTranslationSurnameEntry

    private enum Field: Hashable {
        case key
        case reading
    }

    /// `nil` = thêm họ mới.
    let original: Entry?
    let onSave: (_ key: String, _ reading: String) -> String?
    let onRestoreBundledReading: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var key: String
    @State private var reading: String
    /// Lỗi do màn danh sách trả về lúc ghi; xoá khi người dùng sửa tiếp.
    @State private var saveError: String?

    init(
        original: Entry?,
        onSave: @escaping (_ key: String, _ reading: String) -> String?,
        onRestoreBundledReading: @escaping () -> Void = {}
    ) {
        self.original = original
        self.onSave = onSave
        self.onRestoreBundledReading = onRestoreBundledReading
        _key = State(initialValue: original?.key ?? "")
        _reading = State(initialValue: original?.reading ?? "")
    }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedReading: String { reading.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var keyError: String? {
        QuickTranslationSurnameStore.shared.keyError(trimmedKey, replacing: original?.key)
    }

    private var readingError: String? {
        QuickTranslationSurnameStore.shared.readingError(trimmedReading)
    }

    private var isDirty: Bool {
        trimmedKey != (original?.key ?? "") || trimmedReading != (original?.reading ?? "")
    }

    private var canSave: Bool { isDirty && keyError == nil && readingError == nil }

    var body: some View {
        NavigationStack {
            Form { Group {
                Section {
                    TextField("王 hoặc 欧阳", text: $key)
                        .font(.title3)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .key)
                    if !trimmedKey.isEmpty, let keyError {
                        errorText(keyError)
                    }
                } header: {
                    Text("Họ (chữ Hán)")
                }

                Section {
                    TextField("Vương hoặc Âu Dương", text: $reading)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .reading)
                    if !trimmedReading.isEmpty, let readingError {
                        errorText(readingError)
                    }
                    if let saveError {
                        errorText(saveError)
                    }
                } header: {
                    Text("Âm Hán-Việt")
                }

                if let original, original.isEdited, let bundled = original.bundledReading {
                    Section {
                        Button("Về âm gốc: \(bundled)") {
                            onRestoreBundledReading()
                            dismiss()
                        }
                    }
                }
            }.glassSheetRows() }
            .pageTitle(original == nil ? "Thêm họ" : "Sửa họ")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }
                        .headerTextButton()
                        .disabled(!canSave)
                }
            }
            .onChange(of: key) { _, _ in saveError = nil }
            .onChange(of: reading) { _, _ in saveError = nil }
            .onAppear {
                focusedField = original == nil ? .key : .reading
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
        if let error = onSave(trimmedKey, trimmedReading) {
            saveError = error
            return
        }
        dismiss()
    }
}
