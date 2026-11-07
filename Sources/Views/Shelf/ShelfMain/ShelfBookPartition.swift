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

    /// `nsfwFilter` — bộ lọc NSFW riêng của tab Kệ (`ShelfNsfwFilter`, 1.3.778; trước đó là công tắc NSFW chung):
    /// `.hide` bỏ **mọi** sách NSFW cả trên kệ lẫn lịch sử (chỉ ẩn hiển thị, không xoá), `.only` chỉ giữ sách NSFW, `.all`
    /// giữ hết. "NSFW" = sách của nguồn NSFW hoặc sách người dùng tự đánh dấu (`NsfwBookMarkStore`, kiểm theo `bookId`
    /// **ngoài** bộ nhớ theo nguồn).
    init(_ books: [Book], nsfwFilter: ShelfNsfwFilter = .all) {
        // Partition chạy mỗi body: nhớ kết quả NSFW theo nguồn để mỗi `packageId` chỉ tra kho + classifier một lần.
        var nsfwByPackageId: [String: Bool] = [:]
        let filters = nsfwFilter != .all
        // Đọc tập dấu một lần (cũng là lượt đăng ký Observation: đánh dấu xong Kệ vẽ lại ngay).
        let markedBookIds = filters ? NsfwBookMarkStore.shared.markedBookIds : []
        for book in books where book.isOnShelf || book.isHistory {
            if filters {
                let isNsfw: Bool
                if markedBookIds.contains(book.bookId) {
                    isNsfw = true
                } else if let cached = nsfwByPackageId[book.extensionPackageId] {
                    isNsfw = cached
                } else {
                    let packageId = book.extensionPackageId
                    isNsfw = RepositoryFilterPolicy.isNsfwSource(packageId: packageId)
                    nsfwByPackageId[packageId] = isNsfw
                }
                if !nsfwFilter.keeps(isNsfw: isNsfw) { continue }
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
