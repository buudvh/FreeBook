import Foundation

/// Kết quả quét một file CBZ/ZIP đã giải nén (`LocalComicImporter.prepare`) — dữ liệu của sheet xác nhận
/// "Nhập truyện tranh". Ảnh vẫn nằm trong `workDirectory` cho tới khi người dùng bấm "Nhập".
struct LocalComicImportPlan: Identifiable, Sendable {
    struct Chapter: Identifiable, Sendable {
        /// Vị trí 0-based — cũng là `index` của chương trong mục lục và tên thư mục ở `ComicOfflineStore`.
        let id: Int
        let title: String
        /// Thư mục trong file (đã bỏ thư mục bọc ngoài chung); rỗng = ảnh nằm ở gốc.
        let folderPath: String
        /// Ảnh đã giải nén, xếp theo tên tự nhiên.
        let pages: [URL]
    }

    let id = UUID()
    let fileName: String
    /// Tên file bỏ đuôi — tên truyện mặc định trên sheet.
    let defaultTitle: String
    /// `LocalMediaImportWorkspace` của lượt nhập — xoá cả cây khi nhập xong hoặc bỏ.
    let workDirectory: URL
    let chapters: [Chapter]
    /// Số thư mục con thành chương (0 ⇒ cả file là một chương).
    let folderCount: Int

    var pageCount: Int {
        chapters.reduce(0) { $0 + $1.pages.count }
    }
}
