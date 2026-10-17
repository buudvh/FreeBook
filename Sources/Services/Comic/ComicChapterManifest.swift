import Foundation

/// `manifest.json` của một chương comic đã tải offline (`comics/<sha256(bookId)>/<chapterIndex>/`).
///
/// Manifest chỉ được ghi **sau cùng**, khi mọi ảnh đã nằm trên đĩa: có manifest ⇔ chương tải trọn vẹn.
public struct ComicChapterManifest: Codable, Sendable {
    public struct Page: Codable, Sendable {
        /// Tên file trong thư mục chương (`0001.jpg`), không phải đường dẫn.
        public let file: String
        public let width: Int?
        public let height: Int?

        public init(file: String, width: Int?, height: Int?) {
            self.file = file
            self.width = width
            self.height = height
        }
    }

    public let chapterUrl: String
    public let pages: [Page]
    public let completedAt: Date

    public init(chapterUrl: String, pages: [Page], completedAt: Date) {
        self.chapterUrl = chapterUrl
        self.pages = pages
        self.completedAt = completedAt
    }
}
