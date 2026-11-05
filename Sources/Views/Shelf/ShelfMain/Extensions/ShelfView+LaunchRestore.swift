import SwiftUI

/// Mở lại màn đọc lúc khởi động (1.3.716 — Cài đặt › Đọc & Nghe › Mở lại truyện đang đọc). Kệ là nơi giữ
/// `fullScreenCover` của màn đọc ở tab gốc, nên lượt mở lại đi đúng lối bấm truyện trên Kệ: chương
/// `Book.currentChapterIndex`, vị trí `nil` ⇒ màn chữ về đoạn đã lưu, truyện tranh về ảnh, phim về giây
/// (`BookContentDestination`). TTS đang đọc lúc tắt app thì tiến độ đã thuộc TTS ⇒ mở đúng đoạn TTS, không tự phát.
/// Dấu, công tắc và chốt chống vòng lặp crash ở `ReaderSessionRestoreStore`.
extension ShelfView {
    /// Gọi ở `onAppear` của Kệ; chỉ lượt đầu tiên của tiến trình có tác dụng.
    @MainActor
    func restoreReaderSessionIfNeeded() {
        guard let bookId = ReaderSessionRestoreStore.takeLaunchCandidate() else { return }
        // `@Query` lấy cả truyện 18+ bị ẩn ⇒ tra ở đây được, lọc 18+ bằng đúng luật Kệ dùng để ẩn.
        guard let book = allBooks.first(where: { $0.bookId == bookId }) else {
            AppLogger.shared.log("↩️ [ReaderRestore] Truyện đang đọc lúc tắt app không còn trên máy ⇒ không mở lại")
            ReaderSessionRestoreStore.markClosed()
            return
        }
        if RepositoryFilterPolicy.isNsfwBook(bookId: book.bookId, packageId: book.extensionPackageId) {
            AppLogger.shared.log("↩️ [ReaderRestore] Truyện 18+ ⇒ không tự mở lại màn đọc")
            ReaderSessionRestoreStore.markClosed()
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
        AppLogger.shared.log("↩️ [ReaderRestore] Mở lại màn đọc lúc tắt app: chương \(book.currentChapterIndex), vị trí \(book.currentChapterPage)")
        Task { @MainActor in
            // Một nhịp cho cây view lúc khởi động dựng xong: đặt cover ngay lượt mount đầu có thể bị SwiftUI bỏ qua.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard readerPresentationRoute == nil else {
                // Người dùng đã kịp mở thứ khác ⇒ thôi, không tính là lượt thử.
                ReaderSessionRestoreStore.confirmRestoreSurvived()
                return
            }
            readerPresentationRoute = route
            try? await Task.sleep(nanoseconds: ReaderSessionRestoreStore.survivalDelayNanoseconds)
            ReaderSessionRestoreStore.confirmRestoreSurvived()
        }
    }

    /// `onDismiss` của cover màn đọc: còn route ⇒ cover chỉ được thay bằng màn đọc khác (màn mới tự ghi dấu), không xoá.
    @MainActor
    func readerCoverDidDismiss() {
        if readerPresentationRoute == nil { ReaderSessionRestoreStore.markClosed() }
    }
}
