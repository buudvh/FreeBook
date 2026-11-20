import SwiftUI
import SwiftData

/// Sheet chọn truyện đích để chia sẻ từ điển riêng (hoặc cả bộ rule riêng) từ truyện này sang truyện khác.
/// Chọn truyện **trước** ⇒ popup 3 cách nhập vào truyện đích (`dataImportModePopup`, tên truyện đã chọn ở dòng dưới tiêu
/// đề, nút cuối "Chia sẻ") ⇒
/// `onConfirm(truyện, chế độ)` rồi đóng sheet.
struct BookShareTargetSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let excludedBookId: String?
    let onConfirm: (Book, DataImportMode) -> Void

    @State private var books: [Book] = []
    @State private var pendingTarget: Book? = nil
    @State private var showingModeDialog = false
    @State private var searchQuery = ""

    /// Tên (đã dịch theo cấu hình của truyện) của truyện vừa chọn — tiêu đề popup chọn cách nhập.
    private var pendingTitle: String {
        guard let book = pendingTarget else { return "truyện khác" }
        return BookDisplayTranslation.text(book.title, BookDisplayTranslation.options(for: book))
    }

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lọc realtime theo tên truyện (kèm tên dịch / đã chuyển phồn → giản) và tác giả, dùng chung matcher với Kệ sách.
    private var filteredBooks: [Book] {
        guard !trimmedQuery.isEmpty else { return books }
        let config = TranslationConfigStore.shared.snapshot()
        return books.filter { ShelfBookSearchMatcher.matches(query: trimmedQuery, book: $0, config: config) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BookSearchBarView(text: $searchQuery)
                Divider()
                List(filteredBooks) { book in Group {
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
                }.glassSheetRows() }
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
            .pageTitle("Chọn truyện đích")
            .presentationDragIndicator(.visible)
            .dataImportModePopup(
                isPresented: $showingModeDialog,
                title: "Chia sẻ sang truyện khác",
                message: pendingTitle,
                confirmTitle: "Chia sẻ",
                confirmSystemImage: "arrowshape.turn.up.right"
            ) { mode in
                if let target = pendingTarget {
                    onConfirm(target, mode)
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
    /// Chỉ truyện chữ (2026-11-09): từ điển VP/Name chỉ dùng cho truyện chữ ⇒ bỏ truyện tranh, phim, âm thanh — loại suy
    /// đúng như router mở sách (`BookContentKindResolver`).
    private func loadBooks() {
        let descriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\Book.lastReadDate, order: .reverse)])
        let includeNsfw = RepositoryFilterPolicy.includesNsfwPreference
        books = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter {
                $0.bookId != excludedBookId
                    && (includeNsfw || !RepositoryFilterPolicy.isNsfwBook(bookId: $0.bookId, packageId: $0.extensionPackageId))
                    && BookContentKindResolver.isTextBook(bookId: $0.bookId, packageId: $0.extensionPackageId)
            }
    }
}
