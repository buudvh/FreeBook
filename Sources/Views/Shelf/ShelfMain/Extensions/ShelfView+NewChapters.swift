import SwiftUI
import SwiftData

/// Phần "hộp thư chương mới" của Kệ sách: dựng target, badge và ba đường refresh.
///
/// Tách sang file riêng để `ShelfView.swift` không phình thêm. Toàn bộ logic mạng/lưu trữ nằm ở
/// [`NewChapterInboxManager`](../../../../Services/NewChapters/NewChapterInboxManager.swift);
/// ở đây chỉ có việc gom dữ liệu từ `@Query` và hiện toast — service không được gọi `ToastManager`.
@MainActor
extension ShelfView {
    /// Truyện online trên kệ, **theo thứ tự đọc gần nhất** (`allBooks` đã sort giảm dần theo
    /// `lastReadDate`) nên khi lượt kiểm tra bị chặn bởi `maxBooksPerBatch` thì truyện đang đọc
    /// được ưu tiên.
    internal var newChapterTargets: [NewChapterProbe.Target] {
        allBooks.compactMap { book in
            guard book.isOnShelf else { return nil }
            return newChapterTarget(for: book)
        }
    }

    /// `nil` khi truyện không thể kiểm tra: truyện nhập cục bộ, thiếu `detailUrl`, hoặc tiện ích
    /// bóc tách chưa tải về máy. Thân hàm ở `BookActionRunner` để màn Bộ sưu tập dùng chung.
    internal func newChapterTarget(for book: Book) -> NewChapterProbe.Target? {
        BookActionRunner.newChapterTarget(for: book, extensions: allExtensions)
    }

    // MARK: - Ba đường refresh

    /// Lượt tự động lúc mở Kệ sách: dọn record của truyện đã xoá rồi kiểm tra nếu qua cửa cooldown.
    /// Chạy trong `.task` nên **không** chặn khởi động; im lặng khi không có gì mới.
    internal func runAutoNewChapterCheck() async {
        await newChapters.loadIfNeeded()
        await newChapters.prune(keeping: Set(allBooks.map { $0.bookId }))
        let targets = newChapterTargets
        guard !targets.isEmpty else { return }
        guard let summary = await newChapters.autoCheck(targets: targets) else { return }
        BookActionRunner.showNewChapterSummary(summary, announceEmpty: false)
    }

    /// Refresh tay toàn bộ kệ — bỏ qua cooldown, luôn báo kết quả.
    internal func checkAllNewChapters() {
        let targets = newChapterTargets
        guard !targets.isEmpty else {
            ToastManager.shared.show(message: "Không có truyện online nào trên kệ để kiểm tra")
            return
        }
        Task {
            guard let summary = await newChapters.checkAll(targets: targets) else { return }
            BookActionRunner.showNewChapterSummary(summary, announceEmpty: true)
        }
    }

    /// Refresh tay một truyện.
    internal func checkNewChapters(for book: Book) {
        BookActionRunner.checkNewChapters(for: book, extensions: allExtensions)
    }
}
