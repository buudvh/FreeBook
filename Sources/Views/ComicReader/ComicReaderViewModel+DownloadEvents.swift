import Foundation

/// Mục lục comic đổi icon "đã tải" ngay khi tác vụ tải ảnh offline lưu xong một chương (1.3.713).
///
/// Trước đây `downloadedChapterIndexes` chỉ đọc đĩa một lần trong `start()`, nên bấm tải ở mục lục rồi chờ thì icon
/// đứng yên tới khi mở lại màn đọc. `ComicOfflineStore.saveManifest` giờ báo `ChapterDownloadEventCenter`.
extension ComicReaderViewModel {

    /// Chạy trong `.task` của `ComicReaderView`. Mở trình xem phóng to / trình duyệt "Mở link lỗi" (đều là
    /// `fullScreenCover`) làm màn biến mất rồi hiện lại ⇒ Task bị huỷ rồi chạy lại; sự kiện lúc đó bị lỡ nên mỗi lần chạy
    /// đọc lại đĩa (ngoài main) trước. Stream tạo **trước** khi đọc đĩa nên chương xong giữa chừng vẫn nằm chờ trong stream.
    func observeChapterDownloads() async {
        let bookId = launch.bookId
        guard !bookId.isEmpty else { return }
        let stream = ChapterDownloadEventCenter.shared.chapterIndices(bookId: bookId)
        let downloaded = await Task.detached(priority: .utility) {
            ComicOfflineStore.downloadedChapterIndexes(bookId: bookId)
        }.value
        guard !Task.isCancelled else { return }
        if downloadedChapterIndexes != downloaded {
            downloadedChapterIndexes = downloaded
        }
        for await indices in stream where !Set(indices).isSubset(of: downloadedChapterIndexes) {
            downloadedChapterIndexes.formUnion(indices)
        }
    }
}
