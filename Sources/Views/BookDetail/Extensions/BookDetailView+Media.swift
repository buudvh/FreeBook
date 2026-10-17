import SwiftUI

/// Cờ hiển thị của màn chi tiết theo **loại nội dung** của nguồn (truyện chữ / truyện tranh / video).
///
/// Loại suy lúc chạy qua `ExtensionContentKind.resolve(packageId:)` — không lưu vào `Book` (bất biến 4 của plan
/// comic/video). Dịch tên truyện và tên chương vẫn giữ cho mọi loại (có ích với manhua).
extension BookDetailView {
    internal var contentKind: ExtensionContentKind {
        ExtensionContentKind.resolve(packageId: extensionPackageId)
    }

    /// Xuất ebook chỉ có nghĩa với truyện chữ.
    internal var showsExport: Bool {
        !contentKind.isMedia
    }

    /// Từ điển riêng của truyện chỉ phục vụ dịch nội dung chữ.
    internal var showsDictionaryMenu: Bool {
        !contentKind.isMedia
    }

    /// Nhãn nút tải; `nil` = ẩn nút (video chưa hỗ trợ tải offline).
    internal var downloadActionTitle: String? {
        switch contentKind {
        case .comic: return "Tải ảnh offline"
        case .video: return nil
        case .text, .unsupported: return "Tải truyện"
        }
    }

    /// "Đọc ngay"/"Đọc tiếp" cho truyện, "Xem ngay"/"Xem tiếp" cho video.
    internal func readActionTitle(isResuming: Bool) -> String {
        if contentKind == .video {
            return isResuming ? "Xem tiếp" : "Xem ngay"
        }
        return isResuming ? "Đọc tiếp" : "Đọc ngay"
    }

    /// Danh từ cho một mục của mục lục: "chương" hoặc "tập".
    internal var episodeNoun: String {
        contentKind == .video ? "tập" : "chương"
    }
}
