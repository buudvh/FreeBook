import SwiftUI
import SwiftData

/// Nút ⋮ + chế độ **chọn nhiều** của hai trang Kệ Sách / Lịch Sử (anh Bửu duyệt mockup
/// https://claude.ai/artifact/Es6YfEe94Zyi2uigCzMTPX).
///
/// - ⋮ trên mỗi hàng / thẻ mở `BookActionSheet` (trước đây là việc của nhấn giữ).
/// - Nhấn giữ ⇒ rung + vào chế độ chọn, truyện đó chọn sẵn (`ShelfBookSelection`, chỉ giữ `bookId`). Header thành ✕ +
///   "Đã chọn N" + "Chọn tất cả" / "Bỏ chọn tất cả"; 🔍, "…" và nút "+" nổi ẩn; thanh thao tác (`ShelfSelectionActionBar`)
///   đè lên thanh tab. "Chọn tất cả" = mọi truyện đang hiện của trang (chip loại + NSFW), kể cả phần chưa phân trang tới.
/// - Thoát: ✕, đổi trang Kệ (bấm hàng tab hoặc vuốt), mở Reader từ thông báo / đĩa nghe, thao tác xong.
///
/// Bộ sưu tập và Tìm trên kệ không dùng khối này (nhấn giữ vẫn mở sheet). Mọi lệnh ghi đi qua coordinator
/// (`BookTransactionCoordinator+Batch`, `BookCollectionCoordinator.addBooks`); xoá khỏi máy qua `BookStorageManager`.
@MainActor
extension ShelfView {
    // MARK: - Vào / ra

    /// Nhấn giữ một truyện ở trang `page` (chỉ `.shelf` / `.history`).
    func enterSelection(_ book: Book, page: ShelfTab) {
        BookSheetAction.playLongPressFeedback()
        bookSelection = ShelfBookSelection(page: page, bookId: book.bookId)
    }

    /// ⋮ của một truyện — đúng sheet mà nhấn giữ từng mở.
    func openBookActions(_ book: Book, mode: BookSheetAction.Mode) {
        actionTarget = BookSheetAction.Target(book: book, mode: mode)
    }

    /// Cấu hình chọn cho `ShelfBooksLayoutView` của trang `page`; `nil` khi không chọn (hoặc đang chọn ở trang kia).
    func selectionConfig(for page: ShelfTab) -> ShelfBooksLayoutView.Selection? {
        guard let selection = bookSelection, selection.page == page else { return nil }
        return ShelfBooksLayoutView.Selection(selectedIds: selection.ids) { book in
            bookSelection?.toggle(book.bookId)
        }
    }

    // MARK: - Header

    /// Truyện đang hiện của trang đang chọn, đủ cả phần chưa phân trang tới.
    func selectionPageBooks(_ filter: ShelfKindFilter) -> [Book] {
        switch bookSelection?.page {
        case .shelf?: return filter.pinned + filter.unpinned
        case .history?: return filter.history
        default: return []
        }
    }

    /// Tiêu đề header: "Đã chọn N" khi đang chọn, không thì tiêu đề trang.
    func headerTitle(_ filter: ShelfKindFilter) -> String {
        guard let selection = bookSelection else { return selectedTab.navigationTitle }
        return "Đã chọn \(selection.count(in: selectionPageBooks(filter)))"
    }

    /// ✕ trước tiêu đề (`HeaderLeadingIconButton`) — chỉ khi đang chọn.
    var selectionExitButton: HeaderLeadingIconButton? {
        guard bookSelection != nil else { return nil }
        return HeaderLeadingIconButton(systemName: "xmark", accessibilityLabel: "Thoát chọn nhiều") {
            bookSelection = nil
        }
    }

    /// Nút chữ bên phải header khi đang chọn: "Chọn tất cả", đã chọn đủ thì "Bỏ chọn tất cả".
    func selectAllButton(_ filter: ShelfKindFilter) -> some View {
        let books = selectionPageBooks(filter)
        let allSelected = bookSelection?.containsAll(books) == true
        return Button(allSelected ? "Bỏ chọn tất cả" : "Chọn tất cả") {
            if allSelected {
                bookSelection?.deselectAll()
            } else {
                bookSelection?.selectAll(books)
            }
        }
        .headerTextButton()
        .disabled(books.isEmpty)
    }

    // MARK: - Thanh thao tác

    /// Gắn bằng `overlay(alignment: .bottom)` ngay sau `.mainTabBar()` ⇒ đè đúng chỗ thanh tab.
    @ViewBuilder
    func selectionActionBar(_ filter: ShelfKindFilter) -> some View {
        if let selection = bookSelection {
            ShelfSelectionActionBar(
                page: selection.page,
                books: selection.selectedBooks(in: selectionPageBooks(filter)),
                onDelete: { choice, books in
                    performSelectionDelete(choice, books: books)
                },
                onFinished: {
                    bookSelection = nil
                }
            )
        }
    }

    // MARK: - Xoá

    private func performSelectionDelete(_ choice: ShelfSelectionActionBar.DeleteChoice, books: [Book]) {
        guard !books.isEmpty else { return }
        // Tách nhóm **trước** mọi lệnh ghi (đọc cờ kệ của `Book` khi chưa đổi).
        let ids = books.map(\.bookId)
        let onShelfIds = books.filter(\.isOnShelf).map(\.bookId)
        let offShelfIds = books.filter { !$0.isOnShelf }.map(\.bookId)
        bookSelection = nil

        switch choice {
        case .removeFromShelf:
            switch BookTransactionCoordinator.shared.removeFromShelf(bookIds: ids, in: modelContext) {
            case .success(let count):
                ToastManager.shared.show(message: "Đã bỏ \(count) truyện khỏi kệ sách", type: .success)
            case .failure(let error):
                AppLogger.shared.log("❌ [ShelfSelection] Lỗi bỏ \(ids.count) truyện khỏi kệ: \(error.localizedDescription)")
                ToastManager.shared.show(message: "Không thể bỏ khỏi kệ sách: \(error.localizedDescription)", type: .error)
            }
        case .deleteFromDevice:
            deleteSelectedFromDevice(ids, alreadyDone: 0) { "Đã xoá \($0) truyện khỏi máy" }
        case .removeFromHistory:
            // Như "Xoá lịch sử" từng truyện (`BookActionRunner.removeFromHistory`): trên kệ ⇒ chỉ rời Lịch sử; không ở kệ ⇒
            // xoá khỏi máy.
            var historyOnlyCount = 0
            if !onShelfIds.isEmpty {
                switch BookTransactionCoordinator.shared.setHistory(bookIds: onShelfIds, isHistory: false, in: modelContext) {
                case .success(let count):
                    historyOnlyCount = count
                case .failure(let error):
                    AppLogger.shared.log("❌ [ShelfSelection] Lỗi bỏ \(onShelfIds.count) truyện khỏi lịch sử: \(error.localizedDescription)")
                    ToastManager.shared.show(message: "Không thể xoá khỏi lịch sử: \(error.localizedDescription)", type: .error)
                }
            }
            if offShelfIds.isEmpty {
                if historyOnlyCount > 0 {
                    ToastManager.shared.show(message: "Đã xoá \(historyOnlyCount) truyện khỏi lịch sử", type: .success)
                }
            } else {
                deleteSelectedFromDevice(offShelfIds, alreadyDone: historyOnlyCount) { "Đã xoá \($0) truyện khỏi lịch sử" }
            }
        }
    }

    /// Xoá hẳn khỏi máy qua `BookStorageManager.deleteBooksAsync` (một lượt, bật lớp chờ "Đang dọn dẹp sách..."). Hàm đó tự
    /// giữ truyện đang nghe TTS ⇒ toast báo số giữ lại theo số thật đã xoá.
    private func deleteSelectedFromDevice(_ ids: [String], alreadyDone: Int, message: @escaping (Int) -> String) {
        let container = modelContext.container
        isProcessingDeletion = true
        Task { @MainActor in
            do {
                let deleted = try await BookStorageManager.shared.deleteBooksAsync(bookIds: ids, container: container)
                let kept = ids.count - deleted
                var text = message(deleted + alreadyDone)
                if kept > 0 {
                    text += " · giữ lại \(kept) truyện đang nghe"
                }
                ToastManager.shared.show(message: text, type: .success)
            } catch {
                AppLogger.shared.log("❌ [ShelfSelection] Lỗi xoá \(ids.count) truyện khỏi máy: \(error.localizedDescription)")
                ToastManager.shared.show(message: "Không thể xoá: \(error.localizedDescription)", type: .error)
            }
            self.isProcessingDeletion = false
        }
    }
}
