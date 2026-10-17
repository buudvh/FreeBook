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

    /// `hidesNsfwHistory`: công tắc NSFW toàn app đang tắt ⇒ bỏ sách **lịch sử** của nguồn NSFW (chỉ ẩn hiển thị,
    /// không xoá; sách trên kệ không bị ẩn).
    init(_ books: [Book], hidesNsfwHistory: Bool = false) {
        for book in books {
            if book.isOnShelf {
                if book.isPinned {
                    pinned.append(book)
                } else {
                    unpinned.append(book)
                }
            } else if book.isHistory {
                if hidesNsfwHistory && RepositoryFilterPolicy.isNsfwSource(packageId: book.extensionPackageId) { continue }
                history.append(book)
            }
        }
    }
}
