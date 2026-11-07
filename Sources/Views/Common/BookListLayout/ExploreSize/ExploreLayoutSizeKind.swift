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
}
