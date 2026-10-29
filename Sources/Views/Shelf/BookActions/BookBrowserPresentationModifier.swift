import SwiftUI

/// "Mở trong trình duyệt" của sheet nhấn giữ (`BookSheetAction.openInBrowser`): trình duyệt toàn màn mở trang chi tiết
/// của truyện (`detailUrl` + `host` của nguồn). Dùng chung cho ba nơi trình bày `BookActionSheet` — Kệ sách
/// (`ShelfView`), Tìm trên kệ (`ShelfSearchView`), Bộ sưu tập (`CollectionDetailView`).
///
/// - Mỗi nơi xếp truyện vào hàng chờ khi nhận hành động và chỉ gán `book` trong `onDismiss` của sheet nhấn giữ: cover
///   bật lên lúc sheet còn đang trượt xuống thì không hiện (cùng lý do với `queuedShelfRemovalBook`).
/// - Không truyền `onImport`: truyện đã có trong thư viện, trình duyệt chỉ để xem trang nguồn (đăng nhập, vượt chặn…).
/// - `detailUrl` của nguồn Legado có thể kèm khối tuỳ chọn `,{…}` ở cuối ⇒ trang có thể mở không sạch.
struct BookBrowserPresentationModifier: ViewModifier {
    @Binding var book: Book?

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $book) { book in
            BypassWebView(urlString: book.detailUrl, host: book.host)
        }
    }
}

extension View {
    /// Gắn trình duyệt "Mở trong trình duyệt" — `book` khác `nil` ⇒ mở.
    func bookBrowserPresentation(_ book: Binding<Book?>) -> some View {
        modifier(BookBrowserPresentationModifier(book: book))
    }
}
