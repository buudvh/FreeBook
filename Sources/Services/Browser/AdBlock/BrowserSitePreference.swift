import Foundation

/// Chỉnh riêng của một tên miền trong trình duyệt người dùng (menu khiên). `nil` = theo cài đặt chung.
/// Bản ghi có cả hai trường `nil` không được lưu (`BrowserSitePreferenceStore` xoá luôn).
struct BrowserSitePreference: Identifiable, Equatable, Codable, Sendable {
    /// Tên miền đã chuẩn hoá (`BrowserSitePreferenceStore.normalizedDomain(for:)`).
    let domain: String
    var adBlock: Bool?
    var desktop: Bool?

    var id: String { domain }

    var isEmpty: Bool { adBlock == nil && desktop == nil }
}
