import Foundation

/// Việc trang "Từ URL" (`ShelfImportURLStep`, trang con của sheet "Nhập truyện" kiểu hub) đã chọn — `ShelfView` thực thi
/// **sau khi** sheet đóng xong (`ShelfView.runImportChoice`). Trước 1.3.872 là `ShelfImportSheet.Choice` (sheet "Nhập từ URL"
/// riêng ở cửa sổ chính, nay bỏ).
enum ShelfImportChoice: Equatable {
    /// Mở Chi tiết truyện ở `detailUrl` qua tiện ích `packageId` (trang "Từ URL" đã dò ra).
    case openBook(detailUrl: String, packageId: String, sourceName: String)
    /// Mở trình duyệt nhập truyện ở link không tiện ích nào nhận.
    case openBrowser(urlString: String)
}
