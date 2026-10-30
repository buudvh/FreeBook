import Foundation

/// Chỉnh riêng của một tên miền trong trình duyệt người dùng (menu khiên). `nil` = theo cài đặt chung.
/// Bản ghi có mọi trường `nil` không được lưu (`BrowserSitePreferenceStore` xoá luôn).
struct BrowserSitePreference: Identifiable, Equatable, Codable, Sendable {
    /// Tên miền đã chuẩn hoá (`BrowserSitePreferenceStore.normalizedDomain(for:)`).
    let domain: String
    var adBlock: Bool?
    var desktop: Bool?
    /// Tự dịch QT trang của tên miền này (`true`) / không dịch (`false`); `nil` = theo tiện ích khớp URL rồi tắt
    /// (`BrowserTranslatePolicy`). File cũ không có khoá này vẫn đọc được (Codable tổng hợp đọc thiếu khoá thành `nil`).
    var translate: Bool?

    var id: String { domain }

    var isEmpty: Bool { adBlock == nil && desktop == nil && translate == nil }
}
