import SwiftUI

/// Tab Mục lục của Chi tiết đổi icon "đã tải" ngay khi chương tải xong (1.3.713) — bấm tải truyện rồi đứng xem mục lục
/// thì trước đây icon đứng yên, vì `chapterSnapshots` chỉ đọc lại khi tab hiện ra, kéo làm mới hoặc đóng Reader.
///
/// Không đọc lại cả mục lục mỗi chương (đọc DB + dựng lại số thứ tự/lọc hàng nghìn dòng): giữ một tập chỉ số vừa được
/// `ChapterDownloadEventCenter` báo, hàng hiện icon khi `chap.isCached || tập.contains(chap.index)`. Lỡ sự kiện lúc tab bị
/// che/ẩn thì không sao: tab hiện lại là `BookDetailView.tocTab` đọc lại `chapterSnapshots` từ DB.
extension BookDetailTOCView {

    /// Gộp sự kiện tối đa một lần mỗi chừng này (1.3.965).
    private static let eventFlushNanoseconds: UInt64 = 1_000_000_000

    /// Chỉ số chờ gộp + lượt gộp đang hẹn — hộp tham chiếu vì Task không được ghi biến cục bộ của vòng `for await`.
    @MainActor
    final class PendingCachedIndices {
        var indices = Set<Int>()
        var flushTask: Task<Void, Never>?
    }

    /// Chỉ truyện chữ: hàng ở đây lấy cờ từ `ChapterStore`, mà comic báo đã tải theo manifest ảnh (cùng `bookId`) — nghe
    /// cả comic thì icon hiện trong phiên rồi mất khi tab dựng lại.
    ///
    /// **Gộp tối đa 1 lần/giây** (1.3.965): mỗi lần ghi `freshlyCachedIndices` (`@State`) là cả `body` dựng lại, kể cả
    /// `ForEach` hàng nghìn chương — và Chi tiết vẫn dựng lại dù đang nằm dưới Reader. Tải 2–3 luồng là vài chương mỗi
    /// giây ⇒ nghi là một nguồn giật của mục lục Reader mở từ Chi tiết. Icon "đã tải" trễ tối đa 1 giây.
    @MainActor
    func observeChapterDownloads() async {
        guard let book = localBook, !book.bookId.isEmpty,
              ExtensionContentKind.resolve(packageId: book.extensionPackageId) == .text else { return }
        let bookId = book.bookId
        let pending = PendingCachedIndices()
        // Bối cảnh cho log đo main kẹt: tab Mục lục của Chi tiết còn sống (kể cả khi Reader đang che nó).
        MainThreadHangMonitor.shared.noteScreen("mục lục Chi tiết", visible: true)
        // Tab bị ẩn ⇒ `.task` huỷ ⇒ vòng dừng; phần chưa gộp bỏ đi — tab hiện lại đọc lại `chapterSnapshots` từ DB.
        defer {
            pending.flushTask?.cancel()
            MainThreadHangMonitor.shared.noteScreen("mục lục Chi tiết", visible: false)
        }
        for await indices in ChapterDownloadEventCenter.shared.chapterIndices(bookId: bookId) {
            pending.indices.formUnion(indices)
            guard pending.flushTask == nil else { continue }
            pending.flushTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: Self.eventFlushNanoseconds)
                guard !Task.isCancelled else { return }
                let fresh = pending.indices.subtracting(freshlyCachedIndices)
                pending.indices.removeAll()
                pending.flushTask = nil
                if !fresh.isEmpty {
                    freshlyCachedIndices.formUnion(fresh)
                }
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
