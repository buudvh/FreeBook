import Foundation

/// Nguồn **duy nhất** của luật nhớ tự dịch QT cho trình duyệt người dùng. Thứ tự ưu tiên:
/// 1. Chỉnh riêng theo tên miền (`BrowserSitePreferenceStore.preference(forHost:)?.translate`, công tắc trong bảng khiên).
/// 2. Tiện ích **đầu tiên** theo thứ tự `ExtensionUrlMatcher.matches` (trên `ExtensionUrlMatcher.candidates` của bản cài)
///    có `Extension.translateOverride != nil` (công tắc ở Cấu hình tiện ích › Trình duyệt).
/// 3. Tắt.
///
/// Nút dịch trên thanh trình duyệt **không** đi qua đây (chỉ bật/tắt cho tab đang xem, không ghi nhớ).
///
/// `@MainActor` vì đọc `ExtensionLibraryRepository.shared.installed` (View gọi trong `body` thì Observation tự vẽ lại
/// khi bảng tiện ích đổi). Chỉ dò `regexp` của tiện ích có công tắc — thường 0–2 cái — nên gọi ở mỗi lần commit trang
/// không tốn biên dịch regex của mọi tiện ích.
@MainActor
enum BrowserTranslatePolicy {
    static func resolve(urlString: String) -> BrowserTranslateResolution {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return .disabled
        }
        if let siteOverride = BrowserSitePreferenceStore.shared.preference(forHost: host)?.translate {
            return BrowserTranslateResolution(isEnabled: siteOverride, source: .site, siteOverride: siteOverride)
        }
        // Lọc trước khi dò: giữ nguyên thứ tự ứng viên nên "đầu tiên có công tắc" không đổi.
        let candidates = ExtensionUrlMatcher.candidates(from: ExtensionLibraryRepository.shared.installed)
            .filter { $0.translateOverride != nil }
        if !candidates.isEmpty,
           let match = ExtensionUrlMatcher.matches(for: urlString, in: candidates).first,
           let value = match.ext.translateOverride {
            return BrowserTranslateResolution(isEnabled: value, source: .`extension`(name: match.ext.name), siteOverride: nil)
        }
        return .disabled
    }
}
