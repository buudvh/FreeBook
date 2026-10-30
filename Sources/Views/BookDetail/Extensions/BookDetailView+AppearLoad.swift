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
        if !tocErrorMessage.isEmpty { loadTOCDataOnly() }
    }
}
