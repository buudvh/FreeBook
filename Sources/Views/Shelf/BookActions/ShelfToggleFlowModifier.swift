import SwiftUI
import SwiftData

/// Luồng của nút icon thêm/bỏ kệ trong danh sách chương Reader chữ và mục lục comic.
///
/// - Thêm: `BookActionRunner.addToShelf` (tự toast) rồi mở `CollectionPickerSheet` — giống màn Chi tiết.
/// - Bỏ: hỏi xác nhận rồi `BookActionRunner.removeFromShelfOnly` — truyện rời kệ, rời mọi bộ sưu tập và bỏ ghim,
///   nhưng giữ file/tiến độ và về Lịch sử. **Không** dùng `BookDetailView.removeFromShelf`: đường đó xoá hẳn truyện
///   (`BookStorageManager.deleteBookAsync`), trong khi truyện đang mở ngay trong Reader.
/// - Hộp xác nhận và sheet chọn bộ sưu tập gắn ở gốc view của nơi dùng, không gắn trong `ToolbarItem`.
/// - Icon dùng lại cặp của công tắc kệ ở `BookActionSheet`: `bookmark.fill` / `bookmark.slash.fill` (đỏ).
///
/// `displayTitle` là tên **đang hiển thị** (đã dịch nếu bật dịch) — `book.title` thô có thể là chữ Hán.
struct ShelfToggleFlowModifier: ViewModifier {
    let book: Book?
    let displayTitle: String
    @Binding var isConfirmingRemoval: Bool
    @Binding var collectionPickerBook: Book?

    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content
            .alert("Bỏ \"\(displayTitle)\" khỏi kệ?", isPresented: $isConfirmingRemoval) {
                Button("Huỷ", role: .cancel) {}
                Button("Bỏ khỏi kệ", role: .destructive) {
                    if let book {
                        BookActionRunner.removeFromShelfOnly(book, in: modelContext)
                    }
                }
            } message: {
                Text("Truyện sẽ rời mọi bộ sưu tập và bỏ ghim. Tiến độ đọc và chương đã tải vẫn giữ, truyện chuyển sang Lịch sử.")
            }
            .sheet(item: $collectionPickerBook) { book in
                CollectionPickerSheet(bookId: book.bookId)
            }
    }

    static func iconName(isOnShelf: Bool) -> String {
        isOnShelf ? "bookmark.slash.fill" : "bookmark.fill"
    }

    static func accessibilityLabel(isOnShelf: Bool) -> String {
        isOnShelf ? "Xoá khỏi kệ sách" : "Thêm vào kệ sách"
    }

    /// Bấm nút: chưa ở kệ ⇒ thêm rồi mời chọn bộ sưu tập; đã ở kệ ⇒ mở hộp xác nhận.
    @MainActor
    static func toggle(
        _ book: Book,
        in context: ModelContext,
        isConfirmingRemoval: Binding<Bool>,
        collectionPickerBook: Binding<Book?>
    ) {
        if book.isOnShelf {
            isConfirmingRemoval.wrappedValue = true
            return
        }
        BookActionRunner.addToShelf(book, in: context)
        // `addToShelf` tự toast khi lỗi; chỉ mời chọn bộ sưu tập khi cờ đã thật sự bật.
        if book.isOnShelf {
            collectionPickerBook.wrappedValue = book
        }
    }
}

extension View {
    func shelfToggleFlow(
        book: Book?,
        displayTitle: String,
        isConfirmingRemoval: Binding<Bool>,
        collectionPickerBook: Binding<Book?>
    ) -> some View {
        modifier(ShelfToggleFlowModifier(
            book: book,
            displayTitle: displayTitle,
            isConfirmingRemoval: isConfirmingRemoval,
            collectionPickerBook: collectionPickerBook
        ))
    }
}
