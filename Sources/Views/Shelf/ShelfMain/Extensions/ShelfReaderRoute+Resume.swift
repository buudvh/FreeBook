import Foundation

/// Lối mở "ở vị trí đang lưu" dùng chung cho chạm thẻ (Kệ sách, Lịch sử, Bộ sưu tập, Tìm trên kệ) và nút "Đọc tiếp" của sheet
/// tuỳ chọn truyện (`BookContinueReadingStrip`): chương `currentChapterIndex`, vị trí `nil` ⇒ màn đọc tự về đoạn / ảnh / giây
/// đã lưu (`BookContentDestination` chọn Reader / truyện tranh / màn xem / màn nghe). Hai lối dùng chung một chỗ để "Đọc tiếp"
/// luôn mở y như chạm thẻ.
extension ShelfReaderRoute {
    init(resuming book: Book) {
        self.init(
            bookId: book.bookId,
            extensionPackageId: book.extensionPackageId,
            chapterIndex: book.currentChapterIndex,
            paragraphIndex: nil,
            detailUrl: book.detailUrl,
            sourceName: book.sourceName
        )
    }
}
