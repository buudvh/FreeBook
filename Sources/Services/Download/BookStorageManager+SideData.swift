import Foundation

extension BookStorageManager {
    /// Dữ liệu nhỏ theo `bookId` ngoài file nội dung (gọi ở bước dọn file của hai lối xoá truyện, sau khi DB đã lưu):
    /// trạng thái nguồn Legado + dấu trang / ghi chú (1.3.1040, `BookAnnotationStore`). Xoá ghi chú lỗi ⇒ vào hàng đợi
    /// xoá lại như file vật lý khác; Dọn rác cũng bắt file của truyện không còn trong thư viện.
    nonisolated static func deleteBookSideData(bookId: String) async {
        await deleteLegadoState(bookId: bookId)
        if !BookAnnotationStore.delete(bookId: bookId) {
            await MainActor.run {
                BookStorageManager.shared.enqueueFailedDeletion(path: BookAnnotationStore.fileURL(bookId: bookId).path)
            }
        }
        await MainActor.run { BookAnnotationRepository.shared.invalidate(bookId: bookId) }
    }
}
