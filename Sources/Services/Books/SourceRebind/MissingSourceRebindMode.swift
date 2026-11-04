import Foundation

/// Cách xử lý truyện mất nguồn (tiện ích nguồn đã gỡ) khi có tiện ích đã cài khớp link chi tiết — Cài đặt › Thư Viện ›
/// Truyện mất nguồn. Xem `MissingSourceRebindCoordinator`.
enum MissingSourceRebindMode: String, CaseIterable, Identifiable {
    /// Dải báo ở Kệ, bấm "Chuyển" một lần. Mặc định.
    case ask
    /// Tự chuyển khi mở Kệ; truyện khớp từ 2 nguồn trở lên vẫn hiện dải báo để hỏi.
    case auto

    static let defaultsKey = "missingSourceRebindMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return "Hỏi một chạm"
        case .auto: return "Tự chuyển"
        }
    }
}
