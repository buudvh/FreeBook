import SwiftUI
import SwiftData

/// Luồng của nút icon thêm/bỏ kệ trong danh sách chương Reader chữ và mục lục comic.
///
/// - Thêm: `BookActionRunner.addToShelf` (tự toast) rồi mở `CollectionPickerSheet` — giống màn Chi tiết.
/// - Bỏ: **bỏ ngay, không hỏi** (1.3.738) — `BookActionRunner.removeFromShelfOnly` (tự toast): truyện rời kệ, rời mọi bộ
///   sưu tập và bỏ ghim, nhưng giữ file/tiến độ và về Lịch sử. **Không** dùng `BookDetailView.removeFromShelf`: đường đó
///   xoá hẳn truyện (`BookStorageManager.deleteBookAsync`), trong khi truyện đang mở ngay trong Reader.
/// - Sheet chọn bộ sưu tập gắn ở gốc view của nơi dùng, không gắn trong `ToolbarItem`.
/// - Icon dùng lại cặp của công tắc kệ ở `BookActionSheet`: `bookmark.fill` / `bookmark.slash.fill` (đỏ).
struct ShelfToggleFlowModifier: ViewModifier {
    @Binding var collectionPickerBook: Book?

    func body(content: Content) -> some View {
        content
            .sheet(item: $collectionPickerBook) { book in
                Group {
                    CollectionPickerSheet(bookId: book.bookId)
                }
                .appGlassSheet()
            }
    }

    static func iconName(isOnShelf: Bool) -> String {
        isOnShelf ? "bookmark.slash.fill" : "bookmark.fill"
    }

    static func accessibilityLabel(isOnShelf: Bool) -> String {
        isOnShelf ? "Xoá khỏi kệ sách" : "Thêm vào kệ sách"
    }

    /// Bấm nút: chưa ở kệ ⇒ thêm rồi mời chọn bộ sưu tập; đã ở kệ ⇒ bỏ khỏi kệ ngay.
    @MainActor
    static func toggle(
        _ book: Book,
        in context: ModelContext,
        collectionPickerBook: Binding<Book?>
    ) {
        if book.isOnShelf {
            BookActionRunner.removeFromShelfOnly(book, in: context)
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
    func shelfToggleFlow(collectionPickerBook: Binding<Book?>) -> some View {
        modifier(ShelfToggleFlowModifier(collectionPickerBook: collectionPickerBook))
    }
}
