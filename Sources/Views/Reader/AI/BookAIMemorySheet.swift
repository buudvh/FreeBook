import SwiftUI

/// Màn hình xem và chỉnh sửa trí nhớ dài hạn của AI theo cuốn truyện.
public struct BookAIMemorySheet: View {
    let bookId: String
    @Environment(\.dismiss) private var dismiss

    @State private var characterContext: String = ""
    @State private var plotSummary: String = ""
    @State private var customDictionarySnapshot: String = ""
    @State private var notes: String = ""
    @State private var isSaved: Bool = false

    public init(bookId: String) {
        self.bookId = bookId
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $characterContext)
                        .frame(minHeight: 100)
                        .font(.subheadline)
                } header: {
                    Label("Bối cảnh & Nhân vật", systemImage: "person.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                } footer: {
                    Text("Thông tin về môn phái, phe phái, nhân vật chính và bối cảnh thế giới truyện.")
                }

                Section {
                    TextEditor(text: $plotSummary)
                        .frame(minHeight: 100)
                        .font(.subheadline)
                } header: {
                    Label("Diễn biến cốt truyện", systemImage: "book.pages.fill")
                        .font(.system(size: 13, weight: .semibold))
                } footer: {
                    Text("Tóm tắt các sự kiện lớn và diễn biến tích luỹ qua các chương.")
                }

                if !customDictionarySnapshot.isEmpty {
                    Section {
                        Text(customDictionarySnapshot)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(10)
                    } header: {
                        Label("Từ điển riêng đã ghi nhận", systemImage: "character.book.closed.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }

                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .font(.subheadline)
                } header: {
                    Label("Ghi chú tuỳ chỉnh", systemImage: "note.text")
                        .font(.system(size: 13, weight: .semibold))
                } footer: {
                    Text("Các ghi chú này sẽ tự động nạp vào system prompt cho AI trong mọi phiên trò chuyện của cuốn truyện này.")
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
                        characterContext = ""
                        plotSummary = ""
                        customDictionarySnapshot = ""
                        notes = ""
                        isSaved = false
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
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
        characterContext = mem.characterContext
        plotSummary = mem.plotSummary
        customDictionarySnapshot = mem.customDictionarySnapshot
        notes = mem.notes
    }

    private func saveMemory() {
        var mem = BookAIMemoryStore.shared.loadMemory(for: bookId)
        mem.characterContext = characterContext.trimmingCharacters(in: .whitespacesAndNewlines)
        mem.plotSummary = plotSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        mem.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        BookAIMemoryStore.shared.saveMemory(mem)
        isSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isSaved = false
            dismiss()
        }
    }
}
