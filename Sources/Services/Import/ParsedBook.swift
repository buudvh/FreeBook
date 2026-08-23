import Foundation

/// Kết quả bóc tách một file sách người dùng nhập từ máy.
///
/// Mọi format (TXT / HTML / EPUB / MOBI–AZW3 / PRC / DOCX / FB2 / PDF) đều đổ về đúng type này rồi đi tiếp
/// qua **một** đường ghi duy nhất ở `ShelfView.performImport` (`AddBookToShelfCommand` →
/// `ChapterStore.replaceFullTOC` → `BookBinManager.writeChapterContent` + `upsertCachedChapter`).
/// Vì vậy thêm format mới **không** cần thêm một dòng code lưu trữ nào.
///
/// Các field metadata đều có giá trị mặc định để đường nhập TXT (chỉ có `title` + `chapters`)
/// giữ nguyên hành vi cũ.
struct ParsedBook: Sendable {
    let title: String
    /// `var` vì `ChapterLengthLimiter` thay danh sách chương ở bước hậu xử lý chung của
    /// `BookImportService.parse`, sau parser và trước sheet xác nhận.
    var chapters: [ParserChapter]
    /// `dc:creator` của EPUB / EXTH 100 của MOBI. `nil` ⇒ dùng `"Local"` như TXT.
    var author: String? = nil
    /// `dc:description` của EPUB / EXTH 103 của MOBI.
    var desc: String? = nil
    /// Ảnh bìa nhúng trong file, sẽ ghi qua `ImageCacheManager.saveCover` (không đi qua `coverUrl`).
    var coverData: Data? = nil
    /// Ảnh bìa dạng URL tuyệt đối (chỉ HTML một file mới có).
    var remoteCoverUrl: String? = nil
    /// Mô tả cách đã tách chương, chỉ để hiện trên sheet xác nhận. Không lưu vào CSDL.
    var structureNote: String? = nil
    /// Cảnh báo mất mát nội dung mà người dùng phải tự chấp nhận trước khi nhập (hiện chỉ PDF hỗn hợp:
    /// một phần trang là ảnh scan). `nil` ⇒ sheet xác nhận không hỏi gì thêm.
    var warningNote: String? = nil
}
