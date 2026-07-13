import Foundation
import SwiftData

// @Model: Annotation của SwiftData đánh dấu class này là một Model dữ liệu.
// SwiftData sẽ tự động sinh mã nguồn cần thiết để lưu trữ class này vào cơ sở dữ liệu SQLite dưới nền.
@Model
public final class Book {
    // @Attribute(.unique): Đánh dấu thuộc tính bookId là duy nhất (khóa chính - Primary Key).
    // Dùng để phân biệt các cuốn sách với nhau. ID này thường được gộp từ sourceUrl và detailUrl.
    @Attribute(.unique) public var bookId: String
    public var title: String // Tiêu đề sách
    public var author: String // Tác giả
    public var coverUrl: String // Đường dẫn ảnh bìa (online hoặc local)
    public var desc: String // Mô tả/Giới thiệu sách
    public var detailUrl: String // Đường dẫn chi tiết của sách từ nguồn truyện
    public var sourceName: String // Tên nguồn truyện (ví dụ: TangThuVien, TruyenFull...)
    public var sourceUrl: String // Đường dẫn gốc của nguồn truyện
    public var extensionPackageId: String // ID của extension (plugin JS) phụ trách nguồn truyện này
    public var currentChapterIndex: Int = 0 // Chỉ mục chương đang đọc dở (bắt đầu từ 0)
    public var currentChapterPage: Int = 0 // Vị trí trang hiện tại hoặc vị trí cuộn khi đọc dở
    public var currentChapterTitle: String = "" // Tiêu đề chương đang đọc dở
    public var lastReadDate: Date = Date() // Thời gian đọc cuối cùng (dùng để sắp xếp danh sách đọc gần đây)
    
    public var isOnShelf: Bool = true // Sách có nằm trên Kệ sách chính hay không
    public var isHistory: Bool = false // Sách có nằm trong danh sách Lịch sử đọc hay không
    
    // @Relationship: Định nghĩa mối quan hệ giữa các bảng.
    // deleteRule: .cascade nghĩa là khi xóa cuốn sách này, tất cả các Chương (Chapter) thuộc về nó cũng sẽ tự động bị xóa theo.
    // inverse: \Chapter.book định nghĩa quan hệ ngược lại (mỗi Chapter sẽ tham chiếu ngược về Book chứa nó).
    @Relationship(deleteRule: .cascade, inverse: \Chapter.book)
    public var chapters: [Chapter] = [] // Danh sách các chương của cuốn sách này
    
    // Computed Property (Thuộc tính tính toán): Trả về tiêu đề chương hiển thị trên giao diện.
    // Nếu tiêu đề chương đang đọc dở trống, nó sẽ tìm trong danh sách chapters để lấy tiêu đề tương ứng.
    public var displayChapterTitle: String {
        if !currentChapterTitle.isEmpty {
            return currentChapterTitle
        }
        if let match = chapters.first(where: { $0.index == currentChapterIndex }) {
            return match.title
        }
        return ""
    }
    
    // Hàm khởi tạo (Constructor) để tạo đối tượng Book mới.
    public init(bookId: String, title: String, author: String, coverUrl: String, desc: String, detailUrl: String, sourceName: String, sourceUrl: String, extensionPackageId: String, currentChapterIndex: Int = 0, currentChapterPage: Int = 0, currentChapterTitle: String = "", isOnShelf: Bool = true, isHistory: Bool = false) {
        self.bookId = bookId
        self.title = title
        self.author = author
        self.coverUrl = coverUrl
        self.desc = desc
        self.detailUrl = detailUrl
        self.sourceName = sourceName
        self.sourceUrl = sourceUrl
        self.extensionPackageId = extensionPackageId
        self.currentChapterIndex = currentChapterIndex
        self.currentChapterPage = currentChapterPage
        self.currentChapterTitle = currentChapterTitle
        self.isOnShelf = isOnShelf
        self.isHistory = isHistory
        self.lastReadDate = Date()
    }
}

extension Book: Identifiable {
    public var id: String { bookId }
}
