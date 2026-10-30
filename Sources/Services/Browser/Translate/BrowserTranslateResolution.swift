import Foundation

/// Kết quả luật nhớ tự dịch QT của một trang trong trình duyệt người dùng (`BrowserTranslatePolicy.resolve`).
///
/// - `isEnabled`: trang có tự dịch khi mở không (chưa tính nút dịch bấm tay của tab — thứ đó do
///   `BypassBrowserTabStore` giữ riêng, không ghi nhớ).
/// - `source`: luật nào quyết định — chỉnh riêng theo tên miền, tiện ích khớp URL đầu tiên có công tắc, hay không có gì.
/// - `siteOverride`: giá trị đang lưu theo tên miền (`BrowserSitePreference.translate`); `nil` = chưa chỉnh riêng —
///   bảng khiên dùng để hiện dòng "Dùng cấu hình tiện ích".
struct BrowserTranslateResolution: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case site
        case `extension`(name: String)
        case none
    }

    let isEnabled: Bool
    let source: Source
    let siteOverride: Bool?

    /// Chữ dải báo khi trang **tự** dịch theo luật nhớ; `nil` khi không tự dịch.
    var hintText: String? {
        guard isEnabled else { return nil }
        switch source {
        case .site:
            return "Tự dịch QT · theo tên miền"
        case .`extension`(let name):
            return "Tự dịch QT · theo tiện ích \(name)"
        case .none:
            return nil
        }
    }

    /// Trang không phải web (Home, `about:blank`…) hoặc không luật nào bật.
    static let disabled = BrowserTranslateResolution(isEnabled: false, source: .none, siteOverride: nil)
}
