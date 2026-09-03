import SwiftUI
import SwiftData

/// Phần "đưa truyện lên kệ" của màn Chi tiết: tạo/bật cờ `isOnShelf` rồi mời người dùng chọn bộ sưu
/// tập. Tách khỏi `BookDetailView.swift` để file đó không phình thêm (đang trên baseline dòng).
///
/// Chọn bộ sưu tập là **tuỳ chọn** — bỏ qua sheet thì truyện vẫn ở trên kệ, không thuộc bộ nào.
@MainActor
extension BookDetailView {
    internal func placeOnShelf(savedDesc: String) async {
        let targetBook: Book?
        if let book = localBook {
            let res = BookTransactionCoordinator.shared.setOnShelf(bookId: book.bookId, isOnShelf: true, in: modelContext)
            switch res {
            case .success:
                targetBook = book
            case .failure(let err):
                self.detailErrorMessage = "Lỗi thêm vào kệ: \(err.localizedDescription)"
                return
            }
        } else {
            targetBook = await createBookOnShelf(savedDesc: savedDesc)
        }

        guard let targetBook = targetBook else { return }

        if tocPages.count > 1 && !remainingPagesLoaded {
            startBackgroundRemainingPagesLoading(for: targetBook)
        }

        self.collectionPickerBook = targetBook
    }
}
