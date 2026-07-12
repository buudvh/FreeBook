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

// Thanh tìm kiếm đơn giản
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}
