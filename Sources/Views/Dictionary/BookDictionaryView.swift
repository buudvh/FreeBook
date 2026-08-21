import SwiftUI
import UniformTypeIdentifiers

/// Wrapper that forwards to the new DictionaryHubView.
/// Kept for backward compatibility with existing NavigationLink references
/// in BookDetailView and ReaderView.
struct BookDictionaryView: View {
    let bookId: String
    var bookName: String = ""

    var body: some View {
        DictionaryHubView(bookId: bookId, bookName: bookName)
    }
}
