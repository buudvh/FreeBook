import Foundation

extension ChapterStoreDatabase {
    /// Ghi cờ đã tải của nhiều chương trong **một** transaction (đổi nguồn chép theo lô, 1.3.689). Mỗi lệnh `UPDATE`
    /// autocommit riêng như trước thì 2.000 chương là 2.000 lần commit WAL.
    ///
    /// Tra theo `chapter_index`, không theo url: chương được chép theo **vị trí**, mà hai chương có thể trùng url.
    /// Lỗi ở bất kỳ hàng nào ⇒ rollback cả lô, không để một nửa lô mang cờ đã tải.
    func markChaptersCached(bookId: String, updates: [(index: Int, offset: Int64, length: Int64)]) throws {
        guard !updates.isEmpty else { return }
        try beginTransaction()
        do {
            for update in updates {
                try updateCacheMetadata(
                    bookId: bookId,
                    index: update.index,
                    url: "",
                    isCached: true,
                    offset: update.offset,
                    length: update.length
                )
            }
            try commitTransaction()
        } catch {
            rollbackTransaction()
            throw error
        }
    }
}
