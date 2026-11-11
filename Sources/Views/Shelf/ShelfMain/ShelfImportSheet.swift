import SwiftUI

/// Sheet **"Nhập từ URL"** của Kệ sách (2026-11-11): bước `ShelfImportURLStep` thành một sheet lớn riêng ở cửa sổ chính
/// (có ô nhập + bàn phím). Ba lối nhập (Từ URL / Mở trình duyệt / Từ file) giờ là sheet kiểu hub nằm trên mọi viên thuốc
/// (`ShelfView.presentImportSheet`); chạm "Từ URL" ⇒ sheet đó đóng xong mới mở sheet này — sheet kiểu hub ở cửa sổ phủ
/// không bao giờ key nên không đặt ô nhập chữ trong đó được.
///
/// - Sheet chỉ **báo** lựa chọn qua `onChoose`; `ShelfView` đóng sheet rồi mới làm việc thật trong `onDismiss` (mở
///   Chi tiết / trình duyệt) — xem `ShelfView+ImportEntry`.
struct ShelfImportSheet: View {
    /// Việc người dùng chọn — `ShelfView` thực thi sau khi sheet đóng hẳn.
    enum Choice: Equatable {
        /// Mở Chi tiết truyện ở `detailUrl` qua tiện ích `packageId` (bước "Từ URL" đã dò ra).
        case openBook(detailUrl: String, packageId: String, sourceName: String)
        /// Mở trình duyệt nhập truyện; `"home"` = trang chủ trình duyệt.
        case openBrowser(urlString: String)
    }

    let onChoose: (Choice) -> Void

    var body: some View {
        NavigationStack {
            ShelfImportURLStep(onChoose: onChoose)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
