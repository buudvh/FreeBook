import SwiftUI

/// Cờ hiển thị của màn chi tiết theo **loại nội dung** của nguồn (truyện chữ / truyện tranh). Phim và album âm thanh không
/// mở màn này (mọi lối vào đi `ContentDetailRouter` ⇒ màn xem phim / màn nghe); nếu lọt tới đây thì âm thanh vẫn không có
/// tải / xuất.
///
/// Loại suy lúc chạy qua `ExtensionContentKind.resolve(packageId:)` — không lưu vào `Book` (bất biến 4 của plan
/// comic/video). Dịch tên truyện và tên chương vẫn giữ cho mọi loại (có ích với manhua).
extension BookDetailView {
    internal var contentKind: ExtensionContentKind {
        ExtensionContentKind.resolve(packageId: extensionPackageId)
    }

    /// Truyện nhập từ file (`LocalMediaPackage`): chỉ có bản trên máy — không tải offline.
    internal var isLocalMediaBook: Bool {
        LocalMediaPackage.isLocalMedia(packageId: extensionPackageId)
    }

    /// Xuất file: truyện chữ ra ebook, truyện tranh ra CBZ/PDF (chương đã tải ảnh). Âm thanh chưa xuất được.
    internal var showsExport: Bool {
        contentKind != .audio
    }

    internal var exportActionTitle: String {
        contentKind == .comic ? "Xuất chương đã tải" : "Xuất ebook"
    }

    /// Từ điển riêng của truyện chỉ phục vụ dịch nội dung chữ.
    internal var showsDictionaryMenu: Bool {
        !contentKind.isMedia
    }

    /// Nhãn nút tải; `nil` = ẩn nút (truyện nhập từ file, âm thanh).
    internal var downloadActionTitle: String? {
        guard !isLocalMediaBook, contentKind != .audio else { return nil }
        return contentKind == .comic ? "Tải ảnh offline" : "Tải truyện"
    }

    /// "Đọc ngay" / "Đọc tiếp".
    internal func readActionTitle(isResuming: Bool) -> String {
        isResuming ? "Đọc tiếp" : "Đọc ngay"
    }
}
