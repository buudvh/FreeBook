import SwiftUI

/// Sheet viết / sửa **một** ghi chú của Reader (1.3.1040, anh Bửu duyệt mockup): dòng chương · đoạn, đoạn trích (vạch màu
/// nhấn), ô viết, nút "Lưu" chữ ở header; ghi chú đã có thì thêm hàng "Xoá ghi chú". Không có nút chỉ để đóng (vuốt
/// xuống); gõ dở mà vuốt ⇒ hỏi bỏ. Ghi qua `BookAnnotationRepository`. Chỗ trình bày bọc `Group { … }.appGlassSheet()`.
struct ReaderNoteEditorSheet: View {
    struct Request: Identifiable {
        let id = UUID()
        let bookId: String
        let note: BookAnnotations.Note
        let isNew: Bool
    }

    let request: Request

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var isEditing: Bool

    init(request: Request) {
        self.request = request
        _text = State(initialValue: request.note.text)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDirty: Bool { text != request.note.text }

    var body: some View {
        NavigationStack {
            Form { Group {
                Section {
                    if !request.note.quote.isEmpty {
                        Text(request.note.quote)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 10)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Color.accentColor).frame(width: 3)
                            }
                    }
                    TextField("Viết ghi chú…", text: $text, axis: .vertical)
                        .lineLimit(5...14)
                        .focused($isEditing)
                } header: {
                    Text(Self.locationText(for: request.note))
                }

                if !request.isNew {
                    Section {
                        Button(role: .destructive) {
                            BookAnnotationRepository.shared.deleteNote(bookId: request.bookId, id: request.note.id)
                            ToastManager.shared.show(message: "Đã xoá ghi chú", type: .info, recordsInInbox: false)
                            dismiss()
                        } label: {
                            Label("Xoá ghi chú", systemImage: "trash")
                        }
                    }
                }
            }.glassSheetRows() }
            .pageTitle("Ghi chú")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Lưu") { save() }
                        .headerTextButton()
                        .disabled(trimmed.isEmpty)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .confirmDiscardOnSwipe(isDirty: isDirty)
        .onAppear {
            if request.isNew { isEditing = true }
        }
    }

    private func save() {
        var note = request.note
        note.text = trimmed
        BookAnnotationRepository.shared.saveNote(bookId: request.bookId, note: note)
        ToastManager.shared.show(message: "Đã lưu ghi chú", type: .success, recordsInInbox: false)
        dismiss()
    }

    /// "Chương 12: Bế quan · đoạn 2" (tên chương lúc tạo; tên chương được ghi chú ⇒ không có phần đoạn).
    static func locationText(for note: BookAnnotations.Note) -> String {
        let chapter = note.chapterTitle.isEmpty ? "Chương \(note.chapterIndex + 1)" : note.chapterTitle
        return note.paragraphNumber > 0 ? "\(chapter) · đoạn \(note.paragraphNumber)" : chapter
    }
}
