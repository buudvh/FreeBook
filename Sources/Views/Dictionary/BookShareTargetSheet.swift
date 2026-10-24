import SwiftUI
import SwiftData

/// Sheet chọn truyện đích để chia sẻ từ điển riêng từ truyện này sang truyện khác.
/// Tái sử dụng `dictionaryModeDialog` và `DictionaryTextFileStore.mergedRecords`.
struct BookShareTargetSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let excludedBookId: String?
    let onConfirm: (Book, Bool) -> Void

    @State private var books: [Book] = []
    @State private var pendingTarget: Book? = nil
    @State private var showingModeDialog = false
    @State private var searchQuery = ""

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lọc realtime theo tên truyện (kèm tên dịch) và tác giả, dùng chung matcher với Kệ sách.
    private var filteredBooks: [Book] {
        guard !trimmedQuery.isEmpty else { return books }
        return books.filter {
            ShelfBookSearchMatcher.matches(
                query: trimmedQuery,
                title: $0.title,
                titleTrans: $0.titleTrans,
                author: $0.author,
                authorTrans: $0.authorTrans
            )
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BookSearchBarView(text: $searchQuery)
                Divider()
                List(filteredBooks) { book in
                    Button {
                        pendingTarget = book
                        showingModeDialog = true
                    } label: {
                        // `catalog` gồm cả nguồn chưa cài — vẫn lấy được icon từ registry.
                        let ext = ExtensionLibraryRepository.shared.catalogExtension(packageId: book.extensionPackageId)
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
                .overlay {
                    if filteredBooks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: books.isEmpty ? "book.closed" : "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text(books.isEmpty ? "Không có truyện khác để chia sẻ" : "Không tìm thấy truyện nào")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("Chọn truyện đích")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
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

    /// Công tắc NSFW toàn app tắt ⇒ bỏ **mọi** truyện của nguồn NSFW, kể cả truyện trên kệ (người dùng chốt
    /// 2026-10-24 — chặt hơn Kệ/Lịch sử vốn giữ sách trên kệ). Sheet modal nạp một lần nên đọc công tắc một lần.
    private func loadBooks() {
        let descriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\Book.lastReadDate, order: .reverse)])
        let includeNsfw = RepositoryFilterPolicy.includesNsfwPreference
        books = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter {
                $0.bookId != excludedBookId
                    && (includeNsfw || !RepositoryFilterPolicy.isNsfwSource(packageId: $0.extensionPackageId))
            }
    }
}
