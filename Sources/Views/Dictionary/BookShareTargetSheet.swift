import SwiftUI
import SwiftData

/// Sheet chọn truyện đích để chia sẻ từ điển riêng từ truyện này sang truyện khác.
/// Tái sử dụng `dictionaryModeDialog` và `DictionaryTextFileStore.mergedRecords`.
struct BookShareTargetSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let excludedBookId: String?
    let onConfirm: (Book, Bool) -> Void

    @Query private var allExtensions: [Extension]
    @State private var books: [Book] = []
    @State private var pendingTarget: Book? = nil
    @State private var showingModeDialog = false

    var body: some View {
        NavigationStack {
            List(books) { book in
                Button {
                    pendingTarget = book
                    showingModeDialog = true
                } label: {
                    let ext = allExtensions.first(where: { $0.packageId == book.extensionPackageId })
                    BookListItemView(
                        item: book,
                        showChapter: false,
                        extensionLocalPath: ext?.localPath ?? "",
                        extensionIconUrl: ext?.iconUrl
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Chọn truyện đích")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
            }
            .overlay {
                if books.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "book.closed")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Không có truyện khác để chia sẻ")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .dictionaryModeDialog(
                isPresented: $showingModeDialog,
                title: "Chọn chế độ chia sẻ",
                message: "Thay thế: xóa hết dữ liệu cũ của truyện đích, chỉ giữ từ truyện này.\nGộp: giữ dữ liệu cũ của truyện đích, key trùng lấy giá trị mới."
            ) { isMerge in
                if let target = pendingTarget {
                    onConfirm(target, isMerge)
                    dismiss()
                }
            }
            .task {
                loadBooks()
            }
        }
    }

    private func loadBooks() {
        let descriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\Book.lastReadDate, order: .reverse)])
        books = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { $0.bookId != excludedBookId }
    }
}
