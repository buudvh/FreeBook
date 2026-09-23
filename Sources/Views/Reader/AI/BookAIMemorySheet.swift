import SwiftUI

/// Màn hình xem và chỉnh sửa trí nhớ dài hạn của AI theo cuốn truyện.
public struct BookAIMemorySheet: View {
    let bookId: String
    @Environment(\.dismiss) private var dismiss

    @State private var notes: String = ""
    @State private var isSaved: Bool = false

    public init(bookId: String) {
        self.bookId = bookId
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 180)
                        .font(.subheadline)
                } header: {
                    Text("Ghi nhớ bối cảnh & nhân vật")
                } footer: {
                    Text("Các ghi chú này sẽ tự động được nạp vào trí nhớ của AI trong mọi phiên trò chuyện của cuốn truyện này.")
                }

                if isSaved {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Đã lưu trí nhớ thành công")
                                .foregroundColor(.green)
                                .font(.footnote)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        BookAIMemoryStore.shared.clearMemory(for: bookId)
                        notes = ""
                        isSaved = false
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Xóa toàn bộ trí nhớ truyện này")
                        }
                    }
                }
            }
            .navigationTitle("Trí nhớ truyện")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        saveMemory()
                    }
                    .bold()
                }
            }
            .onAppear {
                loadMemory()
            }
        }
    }

    private func loadMemory() {
        let mem = BookAIMemoryStore.shared.loadMemory(for: bookId)
        notes = mem.notes
    }

    private func saveMemory() {
        var mem = BookAIMemoryStore.shared.loadMemory(for: bookId)
        mem.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        BookAIMemoryStore.shared.saveMemory(mem)
        isSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isSaved = false
            dismiss()
        }
    }
}
