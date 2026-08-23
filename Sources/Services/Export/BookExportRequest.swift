import Foundation

/// Mô tả **bất biến** của một lần xuất truyện: xuất cái gì, dưới định dạng nào, lấy nội dung ở đâu.
///
/// `DownloadManager.executeTask` dựng đúng một `BookExportRequest` cho mỗi tác vụ xuất rồi truyền
/// xuống `ExportRendererFactory` và `ExportContentProvider`. Nhờ DTO này mà renderer không cần biết
/// gì về `DownloadTask`, `Book` hay SwiftData.
public struct BookExportRequest: Sendable {
    public let format: BookExportFormat
    public let bookId: String
    public let bookTitle: String
    public let author: String
    public let desc: String
    /// Ảnh bìa đã lưu local; `nil` khi truyện chưa có bìa hoặc format không nhúng được bìa.
    public let coverJpegData: Data?
    /// Dịch tiêu đề + nội dung chương bằng VietPhrase trước khi render.
    public let translate: Bool
    /// Chỉ lấy chương đã cache, không phát request mạng nào.
    public let cacheOnly: Bool
    /// Tổng số chương nằm trong phạm vi xuất — dùng để báo `đã xuất/thiếu`.
    public let plannedChapterCount: Int

    public init(
        format: BookExportFormat,
        bookId: String,
        bookTitle: String,
        author: String,
        desc: String,
        coverJpegData: Data?,
        translate: Bool,
        cacheOnly: Bool,
        plannedChapterCount: Int
    ) {
        self.format = format
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.author = author
        self.desc = desc
        self.coverJpegData = coverJpegData
        self.translate = translate
        self.cacheOnly = cacheOnly
        self.plannedChapterCount = plannedChapterCount
    }
}
