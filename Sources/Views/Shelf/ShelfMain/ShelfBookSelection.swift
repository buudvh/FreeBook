import Foundation

/// Chế độ chọn nhiều của trang Kệ Sách / Lịch Sử (anh Bửu duyệt mockup https://claude.ai/artifact/Es6YfEe94Zyi2uigCzMTPX):
/// nhấn giữ một truyện ⇒ vào chế độ, truyện đó chọn sẵn (`ShelfView+Selection`).
///
/// Chỉ giữ `bookId`, không giữ `Book`: mọi phép đếm / thao tác đều **giao với danh sách đang hiện** của trang (đã lọc chip
/// loại + NSFW, đủ cả phần chưa phân trang tới), nên truyện bị xoá, bị ẩn hay lọc khỏi trang tự rơi khỏi lựa chọn mà
/// không cần dọn tay.
struct ShelfBookSelection: Equatable {
    /// Trang đang chọn — chỉ `.shelf` hoặc `.history`; đổi trang là thoát chế độ chọn.
    let page: ShelfTab
    private(set) var ids: Set<String>

    init(page: ShelfTab, bookId: String) {
        self.page = page
        self.ids = [bookId]
    }

    mutating func toggle(_ bookId: String) {
        if ids.contains(bookId) {
            ids.remove(bookId)
        } else {
            ids.insert(bookId)
        }
    }

    /// "Chọn tất cả": thay lựa chọn bằng đúng danh sách đang hiện của trang.
    mutating func selectAll(_ books: [Book]) {
        ids = Set(books.map(\.bookId))
    }

    mutating func deselectAll() {
        ids.removeAll()
    }

    /// Truyện đã chọn **còn hiện**, theo thứ tự của trang.
    func selectedBooks(in visible: [Book]) -> [Book] {
        visible.filter { ids.contains($0.bookId) }
    }

    func count(in visible: [Book]) -> Int {
        visible.reduce(0) { ids.contains($1.bookId) ? $0 + 1 : $0 }
    }

    func containsAll(_ visible: [Book]) -> Bool {
        !visible.isEmpty && visible.allSatisfy { ids.contains($0.bookId) }
    }
}
