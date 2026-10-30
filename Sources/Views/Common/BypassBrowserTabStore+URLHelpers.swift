import Foundation
import WebKit

/// Hàm phụ về URL / tên miền của `BypassBrowserTabStore` (chặn cửa sổ bật lên, host trang của tab, rule list hiện
/// hành). Tách khỏi file gốc để file đó không vượt trần dòng; trước đây là `private` trong file gốc.
extension BypassBrowserTabStore {
    /// So với host **khung chính** của trang mở (không theo `sourceFrame`): iframe quảng cáo gọi `window.open` sang
    /// chính tên miền của nó vẫn bị tính là khác tên miền trang.
    func shouldBlockPopup(_ navigationAction: WKNavigationAction, target: URL?, openerHost: String?) -> Bool {
        guard WebContentSettings.popupBlockingEnabled,
              navigationAction.navigationType != .linkActivated else { return false }
        guard let targetHost = target?.host else { return true }
        return !Self.isSameSite(targetHost, openerHost)
    }

    /// Cùng host, hoặc host con/cha của nhau sau khi bỏ `www.` (như `VideoEmbedWebView.Coordinator.host(_:isWithin:)`,
    /// thêm chuẩn hoá để `m.a.com` ↔ `www.a.com` là cùng trang).
    static func isSameSite(_ candidate: String?, _ opener: String?) -> Bool {
        guard let lhs = BrowserSitePreferenceStore.normalizedDomain(for: candidate), !lhs.isEmpty,
              let rhs = BrowserSitePreferenceStore.normalizedDomain(for: opener), !rhs.isEmpty else { return false }
        return lhs == rhs || lhs.hasSuffix("." + rhs) || rhs.hasSuffix("." + lhs)
    }

    /// URL http(s) có host của cửa sổ mới; rỗng, `about:blank`, `data:`, `blob:`… ⇒ `nil` (cửa sổ trống).
    static func webTarget(of url: URL?) -> URL? {
        guard let url, isWebURL(url), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// Host trang tab đang hiển thị; Home / `about:blank` / rỗng / không phải web ⇒ `nil`.
    static func pageHost(of tab: BypassBrowserTab) -> String? {
        let text = tab.urlString
        guard !text.isEmpty, text != "about:blank", text != "Home",
              let url = URL(string: text), isWebURL(url),
              let host = url.host, !host.isEmpty else { return nil }
        return host
    }

    static func currentRuleListIds() -> [ObjectIdentifier] {
        AdBlockRuleListProvider.currentRuleLists().map { ObjectIdentifier($0) }
    }

    static func isWebURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}
