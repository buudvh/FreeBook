import SwiftUI

/// Cờ hiển thị của màn chi tiết theo **loại nội dung** của nguồn (truyện chữ / truyện tranh). Phim không mở màn này
/// (mọi lối vào phim đi `ContentDetailRouter` ⇒ màn xem phim).
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

    /// Xuất file có ở mọi loại: truyện chữ ra ebook, truyện tranh ra CBZ/PDF (chương đã tải ảnh).
    internal var showsExport: Bool {
        true
    }

    internal var exportActionTitle: String {
        contentKind == .comic ? "Xuất chương đã tải" : "Xuất ebook"
    }

    /// Từ điển riêng của truyện chỉ phục vụ dịch nội dung chữ.
    internal var showsDictionaryMenu: Bool {
        !contentKind.isMedia
    }

    /// Nhãn nút tải.
    internal var downloadActionTitle: String? {
        guard !isLocalMediaBook else { return nil }
        return contentKind == .comic ? "Tải ảnh offline" : "Tải truyện"
    }

    /// "Đọc ngay" / "Đọc tiếp".
    internal func readActionTitle(isResuming: Bool) -> String {
        isResuming ? "Đọc tiếp" : "Đọc ngay"
    }
}
