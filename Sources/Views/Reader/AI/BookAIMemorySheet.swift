import SwiftUI

/// Màn hình xem và chỉnh sửa trí nhớ dài hạn của AI (theo từng truyện và trí nhớ tổng toàn cục).
public struct BookAIMemorySheet: View {
    let bookId: String
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Int = 0 // 0: Truyện này, 1: Trí nhớ tổng
    @State private var characterContext: String = ""
    @State private var plotSummary: String = ""
    @State private var customDictionarySnapshot: String = ""
    @State private var notes: String = ""
    @State private var globalMemory: String = ""
    @State private var isSaved: Bool = false

    public init(bookId: String) {
        self.bookId = bookId
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Phạm vi trí nhớ", selection: $selectedTab) {
                    Text("Truyện này").tag(0)
                    Text("Trí nhớ tổng").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Form {
                    if selectedTab == 0 {
                        // TAB 0: TRÍ NHỚ RIÊNG CỦA TRUYỆN NÀY
                        Section {
                            clipboardToolbar(for: $characterContext)
                            TextEditor(text: $characterContext)
                                .frame(minHeight: 90)
                                .font(.subheadline)
                        } header: {
                            Label("Bối cảnh & Nhân vật", systemImage: "person.2.fill")
                                .font(.system(size: 13, weight: .semibold))
                        } footer: {
                            Text("Thông tin về môn phái, phe phái, nhân vật chính và bối cảnh thế giới truyện.")
                        }

                        Section {
                            clipboardToolbar(for: $plotSummary)
                            TextEditor(text: $plotSummary)
                                .frame(minHeight: 90)
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
                            clipboardToolbar(for: $notes)
                            TextEditor(text: $notes)
                                .frame(minHeight: 80)
                                .font(.subheadline)
                        } header: {
                            Label("Ghi chú tuỳ chỉnh", systemImage: "note.text")
                                .font(.system(size: 13, weight: .semibold))
                        } footer: {
                            Text("Tự động nạp vào system prompt trong mọi phiên chat của truyện này.")
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
                    } else {
                        // TAB 1: TRÍ NHỚ TỔNG TOÀN CỤC
                        Section {
                            clipboardToolbar(for: $globalMemory)
                            TextEditor(text: $globalMemory)
                                .frame(minHeight: 220)
                                .font(.system(size: 13, design: .monospaced))
                        } header: {
                            Label("Quy tắc & Chỉ dẫn AI dùng chung", systemImage: "brain.head.profile")
                                .font(.system(size: 13, weight: .semibold))
                        } footer: {
                            Text("Nội dung này được dùng chung cho TẤT CẢ các truyện trong ứng dụng. Mặc định chứa quy tắc lọc tên riêng và định dạng JSON xuất kết quả.")
                        }

                        Section {
                            Button {
                                BookAIMemoryStore.shared.resetGlobalMemoryToDefault()
                                globalMemory = BookAIMemoryStore.shared.loadGlobalMemory()
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Khôi phục quy tắc lọc tên mặc định")
                                }
                                .font(.subheadline)
                            }
                        }
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
                }
            }
            .navigationTitle("Trí nhớ AI")
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

    @ViewBuilder
    private func clipboardToolbar(for text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Spacer()
            Button(action: {
                text.wrappedValue = ""
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .frame(width: 28, height: 26)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(5)
            }
            .buttonStyle(.borderless)
            .disabled(text.wrappedValue.isEmpty)

            Button(action: {
                UIPasteboard.general.string = text.wrappedValue
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .frame(width: 28, height: 26)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(5)
            }
            .buttonStyle(.borderless)
            .disabled(text.wrappedValue.isEmpty)

            Button(action: {
                appendFromClipboard(to: &text.wrappedValue)
            }) {
                Image(systemName: "doc.on.clipboard")
                    .font(.caption)
                    .frame(width: 28, height: 26)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(5)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func appendFromClipboard(to text: inout String) {
        guard let clipboard = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !clipboard.isEmpty else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = clipboard
        } else {
            text = text.hasSuffix("\n") ? "\(text)\(clipboard)" : "\(text)\n\(clipboard)"
        }
    }

    private func loadMemory() {
        let mem = BookAIMemoryStore.shared.loadMemory(for: bookId)
        characterContext = mem.characterContext
        plotSummary = mem.plotSummary
        customDictionarySnapshot = mem.customDictionarySnapshot
        notes = mem.notes
        globalMemory = BookAIMemoryStore.shared.loadGlobalMemory()
    }

    private func saveMemory() {
        // Lưu trí nhớ riêng truyện
        var mem = BookAIMemoryStore.shared.loadMemory(for: bookId)
        mem.characterContext = characterContext.trimmingCharacters(in: .whitespacesAndNewlines)
        mem.plotSummary = plotSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        mem.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        BookAIMemoryStore.shared.saveMemory(mem)

        // Lưu trí nhớ tổng
        BookAIMemoryStore.shared.saveGlobalMemory(globalMemory)

        isSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isSaved = false
            dismiss()
        }
    }
}
