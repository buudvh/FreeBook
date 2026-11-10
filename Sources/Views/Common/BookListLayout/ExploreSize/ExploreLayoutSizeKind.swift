import Foundation

/// Bố cục của trang Khám phá (`explore`) có mức "Cỡ" riêng. `list` dùng chung cho section `list` và `ranking`;
/// section `chip` không có mức cỡ.
///
/// `rawValue` nằm trong khoá `UserDefaults` (`ExploreLayoutSizePreferences.key`) — đổi là mất cỡ đã lưu.
enum ExploreLayoutSizeKind: String, CaseIterable, Identifiable {
    case grid
    case horizontalList
    case list
    case banner

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grid: return "Lưới"
        case .horizontalList: return "Hàng ngang"
        case .list: return "Danh sách & Xếp hạng"
        case .banner: return "Banner"
        }
    }

    /// Nhãn ô của hàng chọn bố cục trong sheet "Kiểu hiển thị" (`ExploreLayoutSizePicker`, 1.3.823) — ngắn cho vừa bốn ô.
    var shortLabel: String {
        switch self {
        case .list: return "Danh sách"
        default: return label
        }
    }

    /// Tên thanh cỡ của bố cục đang chọn trong sheet.
    var sliderTitle: String {
        switch self {
        case .grid, .horizontalList: return "Cỡ thẻ"
        case .list: return "Cỡ dòng"
        case .banner: return "Chiều cao"
        }
    }

    /// Dòng ghi chú dưới thanh cỡ trong sheet.
    var sliderNote: String {
        switch self {
        case .grid: return "Thẻ to hơn thì ít cột hơn."
        case .horizontalList: return "Thẻ to hơn thì rộng hơn, mỗi hàng thấy ít thẻ hơn."
        case .list: return "Áp cho cả mục Danh sách lẫn Xếp hạng."
        case .banner: return "Nấc mặc định là banner 16:9."
        }
    }
}
