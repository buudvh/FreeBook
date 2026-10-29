import SwiftUI
import UniformTypeIdentifiers

/// Wrapper that forwards to the new DictionaryHubView.
/// Kept for backward compatibility with existing NavigationLink references
/// in BookDetailView and ReaderView.
struct BookDictionaryView: View {
    let bookId: String
    var bookName: String = ""
    /// Chuyển tiếp cho `DictionaryHubView`: Reader mở dạng sheet (`true`), Chi tiết truyện đẩy vào (`false`).
    var isPresentedAsSheet = false

    var body: some View {
        DictionaryHubView(bookId: bookId, bookName: bookName, isPresentedAsSheet: isPresentedAsSheet)
    }
}
