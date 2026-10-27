import Foundation

/// Chế độ điện thoại ép buộc của trình duyệt bypass (`forcesMobileUserAgent`, bật khi mở từ nút "Mở link lỗi" —
/// `BypassWebView(urlString:forcesMobileUserAgent: true)`).
///
/// Lý do: `fetch` của tiện ích luôn gửi UA Safari iPhone (`JSExecutor`, trùng `WebUserAgent.mobile`), còn clearance
/// của Cloudflare gắn với UA ⇒ người dùng phải qua xác minh bằng **đúng** UA đó thì cookie chép sang `fetch` mới dùng
/// được. Vì vậy cờ bật thì `desktop = false` ở **mọi** chỗ store tính decision (tạo tab, menu khiên, điều hướng khung
/// chính) — lệch giữa các chỗ sẽ làm `decideMainFrame` tưởng UA vừa đổi và huỷ + nạp lại mỗi chuỗi điều hướng.
///
/// Chỉ ghi đè trong bộ nhớ của phiên duyệt này: tuỳ chọn máy tính đã lưu theo tên miền (`BrowserSitePreferenceStore`)
/// và mặc định chung **không** đổi. Hệ quả: khi cờ bật, công tắc "Xem bản máy tính" ở menu khiên bị khoá
/// (`BypassBrowserShieldButton`).
extension BypassBrowserTabStore {
    /// Decision cho trang ở `host` (`nil` ⇒ theo cài đặt chung), đã áp chế độ điện thoại ép buộc nếu cờ bật.
    /// Dùng cho mọi chỗ cần `desktop` (tạo tab, menu khiên, điều hướng khung chính). Nhánh khung con của
    /// `decidePolicyFor` vẫn gọi thẳng `WebContentPolicy` nhưng chỉ đọc `adBlock` — không bị cờ này ảnh hưởng.
    func policyDecision(host: String?) -> WebContentDecision {
        let decision = WebContentPolicy.decision(for: .userBrowser(host: host))
        guard forcesMobileUserAgent, decision.desktop else { return decision }
        return WebContentDecision(adBlock: decision.adBlock, desktop: false)
    }
}
