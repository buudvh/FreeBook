import SwiftUI
import SwiftData

/// Khối **hành động** của màn tìm trong Kệ sách & Lịch sử: sheet/navigation phụ và bộ chuyển tiếp
/// `BookSheetAction` → `BookActionRunner`.
///
/// Tách khỏi `ShelfSearchView.swift` vì file đó đã tới ~290 dòng và trần của `check_architecture.py`
/// cho file mới là 400. Vì `private` trong Swift là phạm vi **file**, các `@State` mà khối này đọc/ghi
/// phải là `internal` — cùng lý do và cùng khuôn với `ReaderView` + `ReaderView+Selection`.
///
/// Thân của từng hành động nằm ở `BookActionRunner` để màn này cư xử **y hệt** Kệ sách; ở đây chỉ còn
/// phần mở sheet/navigation của riêng màn.
extension ShelfSearchView {

    // MARK: - Sheet & navigation phụ

    @ViewBuilder
    var bookDetailDestinationView: some View {
        if let book = detailTargetBook {
            BookDetailView(
                bookId: book.bookId,
                extensionPackageId: book.extensionPackageId,
                initialDetailUrl: book.detailUrl,
                sourceName: book.sourceName,
                initialHost: book.host
            )
        }
    }

    @ViewBuilder
    var changeSourceDestinationView: some View {
        if let targetBook = changeSourceTargetBook {
            SearchView(
                activeExtensions: activeExtensions,
                selectedExtension: nil,
                initialSearchQuery: targetBook.title,
                changeSourceTargetBook: targetBook,
                onSourceChanged: {
                    changeSourceTargetBook = nil
                    navigateToChangeSource = false
                }
            )
        }
    }

    @ViewBuilder
    var deletionOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Đang dọn dẹp sách...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
        }
        .transition(.opacity)
    }

    // MARK: - Hành động

    func handle(_ action: BookSheetAction, for book: Book) {
        switch action {
        case .openDetail:
            detailTargetBook = book
            navigateToBookDetail = true
        case .checkNewChapters:
            BookActionRunner.checkNewChapters(for: book, extensions: allExtensions)
        case .changeSource:
            changeSourceTargetBook = book
            navigateToChangeSource = true
        case .editInfo:
            editingInfoBook = book
        case .download:
            selectedTaskType = .download
            selectedBookForTask = book
        case .exportEbook:
            selectedTaskType = .exportTxt
            selectedBookForTask = book
        case .retranslateChapterTitles:
            BookActionRunner.retranslateChapterTitles(for: book)
        case .togglePin:
            BookActionRunner.togglePin(book, in: modelContext)
        case .addToShelf:
            BookActionRunner.addToShelf(book, in: modelContext)
        case .removeFromShelfOnly:
            BookActionRunner.removeFromShelfOnly(book, in: modelContext)
        case .removeFromCurrentCollection:
            // Màn này không bao giờ mở sheet ở chế độ `.collection`; giữ nhánh cho `switch` đủ case.
            break
        case .removeFromHistory:
            if BookActionRunner.removeFromHistory(book, in: modelContext) {
                deleteBook(book)
            }
        case .deleteBook:
            deleteBook(book)
        }
    }

    func deleteBook(_ book: Book) {
        let bookId = book.bookId
        let container = modelContext.container
        isProcessingDeletion = true
        Task { @MainActor in
            await BookActionRunner.deleteBook(bookId: bookId, container: container)
            isProcessingDeletion = false
        }
    }
}
