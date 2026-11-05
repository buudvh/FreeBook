import SwiftUI

/// Tab Mục lục của Chi tiết đổi icon "đã tải" ngay khi chương tải xong (1.3.713) — bấm tải truyện rồi đứng xem mục lục
/// thì trước đây icon đứng yên, vì `chapterSnapshots` chỉ đọc lại khi tab hiện ra, kéo làm mới hoặc đóng Reader.
///
/// Không đọc lại cả mục lục mỗi chương (đọc DB + dựng lại số thứ tự/lọc hàng nghìn dòng): giữ một tập chỉ số vừa được
/// `ChapterDownloadEventCenter` báo, hàng hiện icon khi `chap.isCached || tập.contains(chap.index)`. Lỡ sự kiện lúc tab bị
/// che/ẩn thì không sao: tab hiện lại là `BookDetailView.tocTab` đọc lại `chapterSnapshots` từ DB.
extension BookDetailTOCView {

    /// Chỉ truyện chữ: hàng ở đây lấy cờ từ `ChapterStore`, mà comic báo đã tải theo manifest ảnh (cùng `bookId`) — nghe
    /// cả comic thì icon hiện trong phiên rồi mất khi tab dựng lại.
    @MainActor
    func observeChapterDownloads() async {
        guard !isVideo, let book = localBook, !book.bookId.isEmpty,
              ExtensionContentKind.resolve(packageId: book.extensionPackageId) == .text else { return }
        let bookId = book.bookId
        for await indices in ChapterDownloadEventCenter.shared.chapterIndices(bookId: bookId) {
            let fresh = Set(indices).subtracting(freshlyCachedIndices)
            if !fresh.isEmpty {
                freshlyCachedIndices.formUnion(fresh)
            }
        }
    }

    /// `chapterSnapshots` vừa đọc lại từ DB: bỏ khỏi tập những chương DB đã ghi nhận. Không xoá cả tập vì lượt đọc có thể
    /// chạy **trước** lúc chương được ghi mà về sau sự kiện. Số chương đổi (mục lục được cập nhật) thì chỉ số cũ có thể
    /// trỏ sang chương khác ⇒ xoá hết.
    func reconcileFreshlyCached(previousCount: Int) {
        guard !freshlyCachedIndices.isEmpty else { return }
        guard chapterSnapshots.count == previousCount else {
            freshlyCachedIndices.removeAll()
            return
        }
        let cachedInStore = Set(chapterSnapshots.lazy.filter(\.isCached).map(\.index))
        let remaining = freshlyCachedIndices.subtracting(cachedInStore)
        if remaining != freshlyCachedIndices {
            freshlyCachedIndices = remaining
        }
    }
}
