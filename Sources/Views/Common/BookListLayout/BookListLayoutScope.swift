import CoreGraphics

/// Phạm vi lưu kiểu hiển thị: theo **loại nội dung**, dùng chung giữa phía Kệ và Khám phá.
///
/// `all` chỉ có ở phía kệ — kệ trộn nhiều loại khi chip lọc đang ở "Tất cả", và các màn không có chip
/// (Bộ sưu tập, Tìm trên kệ). Khám phá luôn có đúng một loại (loại của nguồn đang xem).
enum BookListLayoutScope: String, CaseIterable, Identifiable {
    case all
    case text
    case comic
    case video

    var id: String { rawValue }

    /// `.unsupported` (tiện ích không duyệt được) rơi về truyện chữ — giống `ExtensionContentKind.resolve`.
    init(kind: ExtensionContentKind) {
        switch kind {
        case .comic: self = .comic
        case .video: self = .video
        case .text, .unsupported: self = .text
        }
    }

    /// Giá trị của `ExtensionKindFilterBar`: `""` (hoặc chuỗi lạ) = "Tất cả", còn lại `ExtensionContentKind.rawValue`.
    init(kindFilter: String) {
        if let kind = SearchExtensionScopePolicy.selectedKind(kindFilter) {
            self.init(kind: kind)
        } else {
            self = .all
        }
    }

    /// Nhãn trùng với nhãn chip loại (`ExtensionContentKind.label`) để "Áp cho: …" khớp chip đang chọn.
    var label: String {
        switch self {
        case .all: return "Tất cả"
        case .text: return ExtensionContentKind.text.label
        case .comic: return ExtensionContentKind.comic.label
        case .video: return ExtensionContentKind.video.label
        }
    }

    /// Tiêu đề nhóm ở màn Cài đặt — nói rõ "Tất cả" áp cho những màn nào.
    var settingsTitle: String {
        switch self {
        case .all: return "Tất cả (Kệ, Lịch sử, Bộ sưu tập, Tìm trên kệ)"
        default: return label
        }
    }

    /// Tỉ lệ rộng : cao của bìa trong lưới. Video luôn ngang 16:9; còn lại (kể cả `all`) đứng 2:3 để các hàng
    /// lưới trộn loại cao bằng nhau.
    var coverAspectRatio: CGFloat {
        self == .video ? 16.0 / 9.0 : 2.0 / 3.0
    }
}
