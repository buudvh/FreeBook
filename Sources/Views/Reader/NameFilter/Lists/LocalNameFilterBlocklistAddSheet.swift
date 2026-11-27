import SwiftUI

/// Sheet **thêm một cụm** vào danh sách "Không phải name" (nút `+` của `LocalNameFilterBlocklistView`): một ô chữ Hán, lỗi
/// hiện ngay dưới ô (luật + trùng lấy từ `LocalNameFilterBlocklistStore.termError`; ô trống không tô đỏ), nút "Thêm" chữ ở
/// header, không nút chỉ để đóng (vuốt xuống; gõ dở thì `confirmDiscardOnSwipe` hỏi lại). Chỗ trình bày bọc
/// `Group { … }.appGlassSheet()`. Ghi do màn danh sách làm (`onAdd` trả chuỗi lỗi nếu không thêm được).
struct LocalNameFilterBlocklistAddSheet: View {
    let onAdd: (_ term: String) -> String?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var term = ""
    /// Lỗi do màn danh sách trả về lúc ghi; xoá khi người dùng sửa tiếp.
    @State private var saveError: String?

    init(onAdd: @escaping (_ term: String) -> String?) {
        self.onAdd = onAdd
    }

    private var trimmedTerm: String { term.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var termError: String? {
        LocalNameFilterBlocklistStore.shared.termError(trimmedTerm)
    }

    private var canAdd: Bool { !trimmedTerm.isEmpty && termError == nil }

    var body: some View {
        NavigationStack {
            Form { Group {
                Section {
                    TextField("唐三做", text: $term)
                        .font(.title3)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .onSubmit { add() }
                    if !trimmedTerm.isEmpty, let termError {
                        errorText(termError)
                    }
                    if let saveError {
                        errorText(saveError)
                    }
                } header: {
                    SectionHelpHeader("Cụm chữ Hán", paragraphs: [
                        "Khớp **nguyên cụm**: thêm 唐三做 chỉ ẩn đúng 唐三做, không làm 唐三 biến mất.",
                        "Danh sách dùng chung mọi truyện, chỉ lọc kết quả của Lọc name local."
                    ])
                }
            }.glassSheetRows() }
            .pageTitle("Thêm cụm")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Thêm") { add() }
                        .headerTextButton()
                        .disabled(!canAdd)
                }
            }
            .onChange(of: term) { _, _ in saveError = nil }
            .onAppear { isFocused = true }
        }
        .confirmDiscardOnSwipe(isDirty: !trimmedTerm.isEmpty)
        .presentationDragIndicator(.visible)
    }

    private func errorText(_ message: String) -> some View {
        Text(verbatim: message)
            .font(.footnote)
            .foregroundColor(.red)
    }

    private func add() {
        guard canAdd else { return }
        if let error = onAdd(trimmedTerm) {
            saveError = error
            return
        }
        dismiss()
    }
}
