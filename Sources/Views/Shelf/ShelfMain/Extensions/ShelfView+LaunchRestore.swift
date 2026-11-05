import SwiftUI

/// Mở lại mục đọc/xem gần nhất lúc khởi động (Cài đặt › Đọc & Nghe › Mở lại truyện đọc gần nhất). Kệ là nơi giữ
/// `fullScreenCover` của màn đọc ở tab gốc, nên lượt mở lại đi đúng lối bấm truyện trên Kệ: chương
/// `Book.currentChapterIndex`, vị trí `nil` ⇒ màn chữ về đoạn đã lưu, truyện tranh về ảnh, phim về giây
/// (`BookContentDestination` chọn màn). TTS đang đọc lúc tắt app thì tiến độ đã thuộc TTS ⇒ mở đúng đoạn TTS, không tự
/// phát. Danh sách mở gần nhất, công tắc và chốt chống vòng lặp crash ở `ReaderSessionRestoreStore`.
extension ShelfView {
    /// Gọi ở `onAppear` của Kệ; chỉ lượt đầu tiên của tiến trình có tác dụng.
    @MainActor
    func restoreReaderSessionIfNeeded() {
        let recentIds = ReaderSessionRestoreStore.takeLaunchCandidates()
        guard !recentIds.isEmpty else { return }
        // `@Query` lấy cả truyện 18+ bị ẩn ⇒ tra ở đây được, rồi bỏ 18+ bằng đúng luật Kệ dùng để ẩn.
        let booksById = Dictionary(allBooks.map { ($0.bookId, $0) }, uniquingKeysWith: { first, _ in first })
        var skippedNsfw = 0
        var target: Book?
        for bookId in recentIds {
            guard let book = booksById[bookId] else { continue }
            // Bản ghi mồ côi (tiện ích tắt lưu lịch sử, không trên kệ): không hiện ở đâu và bị dọn lúc mở app.
            guard book.isOnShelf || book.isHistory || book.isLocalBook else { continue }
            if RepositoryFilterPolicy.isNsfwBook(bookId: book.bookId, packageId: book.extensionPackageId) {
                skippedNsfw += 1
                continue
            }
            target = book
            break
        }
        guard let book = target else {
            AppLogger.shared.log("↩️ [ReaderRestore] Không có mục gần đây để mở lại (bỏ qua \(skippedNsfw) mục 18+)")
            return
        }
        let route = ShelfReaderRoute(
            bookId: book.bookId,
            extensionPackageId: book.extensionPackageId,
            chapterIndex: book.currentChapterIndex,
            paragraphIndex: nil,
            detailUrl: book.detailUrl,
            sourceName: book.sourceName
        )
        ReaderSessionRestoreStore.beginRestoreAttempt(bookId: book.bookId)
        AppLogger.shared.log(
            "↩️ [ReaderRestore] Mở lại mục gần nhất: chương \(book.currentChapterIndex), vị trí \(book.currentChapterPage), bỏ qua \(skippedNsfw) mục 18+"
        )
        Task { @MainActor in
            // Một nhịp cho cây view lúc khởi động dựng xong: đặt cover ngay lượt mount đầu có thể bị SwiftUI bỏ qua.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard readerPresentationRoute == nil else {
                // Người dùng đã kịp mở thứ khác ⇒ thôi, không tính là lượt thử.
                ReaderSessionRestoreStore.finishRestoreAttempt()
                return
            }
            readerPresentationRoute = route
            try? await Task.sleep(nanoseconds: ReaderSessionRestoreStore.survivalDelayNanoseconds)
            ReaderSessionRestoreStore.finishRestoreAttempt()
        }
    }
}
