import Foundation

/// Chia `allBooks` của `ShelfView` thành ba nhóm (ghim / chưa ghim / lịch sử) trong MỘT lượt duyệt,
/// thay cho ba lượt `filter` lặp lại nhiều lần mỗi body. Giữ nguyên thứ tự `lastReadDate` của `@Query`
/// (không `sorted` lại vì `sorted(by:)` của Swift **không ổn định**).
struct ShelfBookPartition {
    private(set) var pinned: [Book] = []
    private(set) var unpinned: [Book] = []
    private(set) var history: [Book] = []

    /// Tương đương `!allBooks.contains { $0.isOnShelf }`.
    var isShelfEmpty: Bool { pinned.isEmpty && unpinned.isEmpty }

    /// `hidesNsfw`: công tắc NSFW toàn app đang tắt ⇒ bỏ **mọi** sách của nguồn NSFW, cả trên kệ lẫn lịch sử (chỉ ẩn
    /// hiển thị, không xoá; người dùng chốt 2026-10-24 — trước đó sách trên kệ vẫn hiện), và sách người dùng tự đánh
    /// dấu NSFW (`NsfwBookMarkStore`, kiểm theo `bookId` **ngoài** bộ nhớ theo nguồn).
    init(_ books: [Book], hidesNsfw: Bool = false) {
        // Partition chạy mỗi body: nhớ kết quả NSFW theo nguồn để mỗi `packageId` chỉ tra kho + classifier một lần.
        var nsfwByPackageId: [String: Bool] = [:]
        // Đọc tập dấu một lần (cũng là lượt đăng ký Observation: đánh dấu xong Kệ vẽ lại ngay).
        let markedBookIds = hidesNsfw ? NsfwBookMarkStore.shared.markedBookIds : []
        for book in books where book.isOnShelf || book.isHistory {
            if hidesNsfw {
                if markedBookIds.contains(book.bookId) { continue }
                let packageId = book.extensionPackageId
                let isNsfw: Bool
                if let cached = nsfwByPackageId[packageId] {
                    isNsfw = cached
                } else {
                    isNsfw = RepositoryFilterPolicy.isNsfwSource(packageId: packageId)
                    nsfwByPackageId[packageId] = isNsfw
                }
                if isNsfw { continue }
            }
            if book.isOnShelf {
                if book.isPinned {
                    pinned.append(book)
                } else {
                    unpinned.append(book)
                }
            } else {
                history.append(book)
            }
        }
    }
}
