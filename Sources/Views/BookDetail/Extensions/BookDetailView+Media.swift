import SwiftUI

/// Cờ hiển thị của màn chi tiết theo **loại nội dung** của nguồn (truyện chữ / truyện tranh / video).
///
/// Loại suy lúc chạy qua `ExtensionContentKind.resolve(packageId:)` — không lưu vào `Book` (bất biến 4 của plan
/// comic/video). Dịch tên truyện và tên chương vẫn giữ cho mọi loại (có ích với manhua).
extension BookDetailView {
    internal var contentKind: ExtensionContentKind {
        ExtensionContentKind.resolve(packageId: extensionPackageId)
    }

    /// Truyện/phim nhập từ file (`LocalMediaPackage`): chỉ có bản trên máy — không tải offline, không xoá bản tải.
    internal var isLocalMediaBook: Bool {
        LocalMediaPackage.isLocalMedia(packageId: extensionPackageId)
    }

    /// Xuất file có ở mọi loại: truyện chữ ra ebook, truyện tranh ra CBZ/PDF (chương đã tải ảnh), video ra file phim
    /// (tập đã tải về máy, `DownloadManager+VideoExport`).
    internal var showsExport: Bool {
        true
    }

    internal var exportActionTitle: String {
        switch contentKind {
        case .video: return "Xuất video"
        case .comic: return "Xuất CBZ/PDF"
        case .text, .unsupported: return "Xuất ebook"
        }
    }

    /// Nút "Xoá bản tải" của phim — không có với phim nhập từ file (xoá là mất phim).
    internal var showsVideoDownloadsPill: Bool {
        contentKind == .video && !isLocalMediaBook
    }

    /// Từ điển riêng của truyện chỉ phục vụ dịch nội dung chữ.
    internal var showsDictionaryMenu: Bool {
        !contentKind.isMedia
    }

    /// Nhãn nút tải (video tải offline qua `DownloadManager+Video`).
    internal var downloadActionTitle: String? {
        guard !isLocalMediaBook else { return nil }
        switch contentKind {
        case .comic: return "Tải ảnh offline"
        case .video: return "Tải video offline"
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
