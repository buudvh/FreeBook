---
paths:
  - "Sources/Services/Browser/**"
  - "Sources/Views/Common/Browser/**"
  - "Sources/Resources/AdBlock/**"
  - "**/*Browser*.swift"
  - "**/*WebView*.swift"
  - "Scripts/update_adblock_snapshot.py"
---

# Chặn quảng cáo & chế độ máy tính (1.3.549)

> Tách từ `AGENTS.md` (1.3.959). Claude Code tự nạp file này khi đọc / sửa file khớp `paths`; agent khác phải tự đọc trước khi sửa phân hệ này.

- **Cơ chế**: `WKContentRuleList` biên dịch từ bộ lọc AdGuard bản tối ưu iOS (`filters.adtidy.org`, id 2/11/214/224 bật sẵn; 19/18/3 tắt sẵn). Chuyển đổi bằng **SafariConverterLib 4.3.1** (SPM, GPL-3.0, có build plugin nên CI cần `-skipPackagePluginValidation`). Mỗi bộ lọc một rule list `adblock-<id>`. Code ở `Sources/Services/Browser/AdBlock/`; bản đóng gói `Sources/Resources/AdBlock/` (tạo lại bằng `Scripts/update_adblock_snapshot.py`, `.gitattributes` giữ CRLF để checksum khớp). Tự cập nhật khi quá hạn `! Expires:` (mặc định 5 ngày).
- **Một nguồn quyết định**: `WebContentPolicy.decision(for:)` → `WebContentDecision { adBlock, desktop }`; `WebContentConfigurator.apply` gắn rule list + UA. Luật ưu tiên: trình duyệt người dùng = chỉnh riêng theo tên miền (`BrowserSitePreferenceStore`) ?? cài đặt chung; webview tiện ích = `Extension.adBlockOverride ?? chung` và `Extension.desktopModeOverride ?? false` (mặc định máy tính của trình duyệt **không** áp sang tiện ích); UA tiện ích tự khai (header track video) thắng chế độ máy tính. Gemini/Google Drive **không** thuộc phạm vi.
- **Chỉ có hiệu lực qua biến thể** `decidePolicyFor:preferences:decisionHandler:` (5 delegate: `BypassBrowserTabStore`, `WebViewLoader`, `VisibleWebViewController`, `VideoEmbedWebView`, `VideoMediaSniffer`). Thêm lại biến thể cũ là WebKit gọi một trong hai — đừng thêm song song.
- `WKContentRuleList` **không** tác động URLSession: `fetch` native của `JSExecutor` vẫn chỉ qua `isEngineDomainBlocked`. Không có API đếm request bị chặn.
- `currentRuleLists()` là bản chụp đồng bộ (lock), rỗng tới khi `warmUp()` (gọi từ `MainTabView`) biên dịch xong — webview tạo trước lúc đó chạy không luật.
- **Dịch QT + menu nhấn giữ của trình duyệt người dùng (1.3.655)**: script dịch (`Services/Browser/Translate/`) và script menu (`Services/Browser/ContextMenu/`) chạy trong **cùng** content world `BrowserPageTranslateScript.contentWorld`. Cài qua `BypassBrowserTabStore.installBrowserSupport(into:)` — **một lần mỗi `WKUserContentController`** (tab `window.open`/`_blank` dùng chung controller của tab mẹ; thêm trùng tên handler là crash). Handler `fbPageTranslate` có trả lời (`addScriptMessageHandler`), `fbContextMenu` không trả lời (`add(_:contentWorld:name:)`). Nhớ dịch: tên miền (`BrowserSitePreference.translate`) ⇒ tiện ích khớp URL (`Extension.translateOverride`) ⇒ tắt (`BrowserTranslatePolicy`). Webview của tab là `BrowserWebView` (lớp con, `buildMenu` thay menu bôi đen) dù `tab.webView` khai `WKWebView`. Phồn → giản là **bước riêng** (1.3.850): tab có hai cờ `isTranslating` + `isConvertingTraditional` (`setPageProcessing(translates:converts:)`), script `enable(mode:)` c / t / ct, trang được xử lý khi bật một trong hai (chỉ chuyển ⇒ giản thể, không dịch); sheet khiên có hàng Phồn → giản ngang hàng "Tự dịch QT".
- Chặn popup chỉ ở trình duyệt người dùng (`createWebViewWith`): script mở sang tên miền khác ⇒ chặn + dải báo; link `.linkActivated` vẫn mở. Chưa kiểm trên máy: popup tạo bằng `a.click()` có bị báo `.linkActivated` không, và tab `window.open` dùng chung `WKUserContentController` với tab mẹ (đã xử lý bằng cách áp lại ở điều hướng kế tiếp).
