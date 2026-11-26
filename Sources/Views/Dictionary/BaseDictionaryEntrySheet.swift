import SwiftUI

/// Sheet thêm **một** mục của từ điển gốc PhienAm hoặc Pronouns, và sửa mục PhienAm (`BaseDictionaryListView`; sửa mục
/// Pronouns dùng màn Sửa từ của VP `DictEntryEditSheet` từ 1.3.1067): hai ô Từ gốc + Nghĩa,
/// nút "Lưu" chữ ở header. Không có nút chỉ để đóng (vuốt xuống); đã gõ dở thì vuốt xuống hỏi bỏ thay đổi.
/// Chỗ trình bày bọc `Group { … }.appGlassSheet()`.
struct BaseDictionaryEntrySheet: View {
    let title: String
    let originalKey: String
    let originalValue: String
    let onSave: (_ key: String, _ value: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var key: String
    @State private var value: String

    init(title: String, originalKey: String = "", originalValue: String = "", onSave: @escaping (String, String) -> Void) {
        self.title = title
        self.originalKey = originalKey
        self.originalValue = originalValue
        self.onSave = onSave
        _key = State(initialValue: originalKey)
        _value = State(initialValue: originalValue)
    }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedValue: String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedKey.isEmpty && !trimmedValue.isEmpty && !trimmedKey.contains("=") }
    private var isDirty: Bool { key != originalKey || value != originalValue }

    var body: some View {
        NavigationStack {
            Form { Group {
                Section("Từ gốc") {
                    TextField("Chữ Trung", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Nghĩa") {
                    TextField("Nghĩa", text: $value, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }.glassSheetRows() }
            .pageTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Lưu") {
                        onSave(trimmedKey, trimmedValue)
                        dismiss()
                    }
                    .headerTextButton()
                    .disabled(!canSave)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .confirmDiscardOnSwipe(isDirty: isDirty)
    }
}
