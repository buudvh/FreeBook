import SwiftUI

/// Tải dữ liệu khi màn Chi tiết hiện ra.
///
/// `onAppear` nổ lại mỗi lần back từ màn con (Xem thêm, bình luận, thể loại, truyện gợi ý…) trong khi `@State` của màn
/// vẫn còn nguyên ⇒ chỉ lần hiện đầu mới tải đủ; các lần sau chỉ phần đang báo lỗi tự thử lại. Muốn lấy mới từ nguồn thì
/// kéo làm mới (`reloadBookData`).
extension BookDetailView {
    func loadBookDataOnAppear() {
        guard hasLoadedBookData else {
            hasLoadedBookData = true
            loadBookData()
            return
        }
        if !detailErrorMessage.isEmpty { loadBookDetailOnly() }
        // Lỗi của lượt "Tải thêm chương" (đã có chương) thì không: `loadTOCDataOnly` sẽ thay danh sách bằng trang 1 và
        // mất các trang đã nối — nút "Tải thêm" ở cuối mục lục vẫn là nút thử lại tay.
        if !tocErrorMessage.isEmpty && onlineChapters.isEmpty { loadTOCDataOnly() }
    }
}
