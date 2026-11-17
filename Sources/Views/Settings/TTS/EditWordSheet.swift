import SwiftUI

/// Sheet **sửa một mục từ điển phiên âm** (từ gốc cố định → cách đọc tiếng Việt). Dùng chung cho màn từ điển của
/// NghiTTS (`TTSDictionaryEditView`) và của VieNeu-TTS (`VieNeuJapaneseDictionaryView`); mỗi màn tự ghi qua `onSave`.
///
/// Tách khỏi `TTSDictionaryEditView.swift` ở 1.3.974 (file đó là legacy nhiều type, baseline dòng chỉ được giảm) cùng
/// lúc thêm **dãy chip gợi ý** (anh Bửu: "thêm chip thay thế vào sửa từ trong từ điển phiên âm của vieneu, nghitts"):
/// `TTSReplacementSuggestionSection` chế độ `.phoneticDictionary` — chip **NGI** / **VIE** (cách đọc đang lưu ở hai từ
/// điển, kể cả mục đang sửa: bấm là trả ô về giá trị đã lưu) + **JP** / **EN** (phiên âm tự động). Bấm chip ⇒ điền
/// cách đọc. Khác sheet Thêm từ ở hai chỗ có chủ ý: không nhấn-giữ-để-xoá (đang sửa chính mục đó), và màn VieNeu vẫn
/// có chip EN (người dùng tự chọn cách đọc, không phải thứ bộ phiên âm sẽ tự chọn).
struct EditWordSheet: View {
    @Environment(\.dismiss) var dismiss
    let key: String
    @State private var value: String
    /// Chip phiên âm của `key` — nạp ngoài main thread bởi `phoneticSuggestions(for:mode:into:)`.
    @State private var suggestions: [TTSPhoneticSuggestion] = []
    let onSave: (String) -> Void

    init(key: String, value: String, onSave: @escaping (String) -> Void) {
        self.key = key
        self._value = State(initialValue: value)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form { Group {
                Section("Sửa phiên âm") {
                    LabeledContent("Từ gốc", value: key)
                        .foregroundStyle(.secondary)

                    TextField("Phiên âm tiếng Việt", text: $value)
                }

                TTSReplacementSuggestionSection(mode: .phoneticDictionary, phonetic: suggestions) { text, _ in
                    value = text
                }
            }.glassSheetRows() }
            .phoneticSuggestions(for: key, mode: .phoneticDictionary, into: $suggestions)
            .pageTitle("Sửa từ")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        onSave(value)
                        dismiss()
                    }
                    .headerTextButton()
                    .disabled(value.trimmed.isEmpty)
                }
            }
        }
        // Mở từ hai màn từ điển phiên âm (NghiTTS, VieNeu): vuốt xuống để đóng, không còn nút Hủy.
        .presentationDragIndicator(.visible)
    }
}
