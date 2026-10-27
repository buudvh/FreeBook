import SwiftUI
import SwiftData

/// Hộp xác nhận **"Bỏ khỏi kệ"** dùng chung: danh sách chương Reader chữ / mục lục comic (qua `ShelfToggleFlowModifier`)
/// và nút kệ của sheet nhấn giữ ở Kệ sách, Tìm trên kệ, Bộ sưu tập — cùng tiêu đề, cùng hai nút, cùng câu giải thích.
///
/// Bấm "Bỏ khỏi kệ" ⇒ `BookActionRunner.removeFromShelfOnly`: truyện rời kệ, rời mọi bộ sưu tập và bỏ ghim, nhưng giữ
/// file/tiến độ và về Lịch sử.
///
/// Dùng `alert(_:isPresented:presenting:)` để nút nhận đúng `Book` lúc hộp hiện: với biến thể `pendingBook`, SwiftUI có
/// thể hạ binding (xoá truyện đang chờ) **trước** khi chạy action — action mà đọc lại state lúc đó sẽ gặp `nil`.
///
/// `displayTitle` là tên **đang hiển thị** (đã dịch nếu bật dịch) — `book.title` thô có thể là chữ Hán.
struct ShelfRemovalConfirmationModifier: ViewModifier {
    let book: Book?
    let displayTitle: String
    @Binding var isPresented: Bool

    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content
            .alert("Bỏ \"\(displayTitle)\" khỏi kệ?", isPresented: $isPresented, presenting: book) { book in
                Button("Huỷ", role: .cancel) {}
                Button("Bỏ khỏi kệ", role: .destructive) {
                    BookActionRunner.removeFromShelfOnly(book, in: modelContext)
                }
            } message: { _ in
                Text("Truyện sẽ rời mọi bộ sưu tập và bỏ ghim. Tiến độ đọc và chương đã tải vẫn giữ, truyện chuyển sang Lịch sử.")
            }
    }
}

extension View {
    func shelfRemovalConfirmation(
        book: Book?,
        displayTitle: String,
        isPresented: Binding<Bool>
    ) -> some View {
        modifier(ShelfRemovalConfirmationModifier(
            book: book,
            displayTitle: displayTitle,
            isPresented: isPresented
        ))
    }

    /// Biến thể cho sheet nhấn giữ: hộp hiện khi `pendingBook` khác `nil`, đóng (bấm nút nào cũng vậy) thì về `nil`.
    /// Tên hiển thị theo đúng luật của hàng truyện (`BookDisplayTranslation.title`) với cờ dịch của màn gọi.
    func shelfRemovalConfirmation(
        pendingBook: Binding<Book?>,
        isTranslationEnabled: Bool
    ) -> some View {
        let book = pendingBook.wrappedValue
        return shelfRemovalConfirmation(
            book: book,
            displayTitle: book.map {
                BookDisplayTranslation.title($0.title, bookId: $0.bookId, isEnabled: isTranslationEnabled)
            } ?? "",
            isPresented: Binding(
                get: { pendingBook.wrappedValue != nil },
                set: { if !$0 { pendingBook.wrappedValue = nil } }
            )
        )
    }
}
