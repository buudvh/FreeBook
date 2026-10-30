import Foundation
import WebKit

/// Dịch trang QT của trình duyệt người dùng: cài script/handler (`installBrowserSupport`), áp luật nhớ khi trang commit,
/// nút dịch bấm tay và áp lại sau khi đổi công tắc nhớ.
///
/// Trạng thái mong muốn của trang = bật/tắt **tay** của tab (`manualTranslate`, chỉ khi trang còn cùng tên miền chuẩn
/// hoá lúc bấm) ?? luật nhớ (`BrowserTranslatePolicy.resolve`). Trang Home / `about:blank` / không phải web ⇒ tắt và
/// quên bật/tắt tay. Trạng thái được **đẩy cả hai chiều** (bật ⇒ `enable`, tắt ⇒ `disable`) ở commit và lúc tải xong:
/// trang khôi phục từ bộ đệm lùi/tiến giữ nguyên DOM đã dịch nên không thể chỉ "không bật".
///
/// `BrowserTranslatePolicy` và hàm gọi JS của `BrowserPageTranslator` là `@MainActor`; gọi qua `MainActor.assumeIsolated`
/// (delegate WebKit chạy trên main) để biên dịch được dù store có được suy luận `@MainActor` hay không.
extension BypassBrowserTabStore {
    // MARK: - Cài script + handler

    /// Cài script dịch + handler `fbPageTranslate` (và phần menu nhấn giữ) vào `controller`, **một lần** mỗi bộ điều
    /// khiển. Bỏ qua chỉ khi controller đã có trong `installedControllers` **và** còn đúng script: `ObjectIdentifier`
    /// có thể bị tái dùng sau khi controller cũ giải phóng.
    func installBrowserSupport(into controller: WKUserContentController) {
        let key = ObjectIdentifier(controller)
        let hasScript = BrowserPageTranslateScript.isInstalled(in: controller)
        if installedControllers.contains(key), hasScript { return }
        installedControllers.insert(key)
        if !hasScript {
            controller.addUserScript(BrowserPageTranslateScript.userScript())
        }
        BrowserPageTranslator.installMessageHandler(into: controller) { [weak self] webView in
            guard let self, let webView, let tab = self.tab(for: webView) else { return false }
            return tab.isTranslating
        }
        installContextMenuSupport(into: controller)
    }

    // MARK: - API cho View

    /// Nút dịch trên thanh: bật/tắt cho **tab này**, không ghi nhớ; giữ khi còn cùng tên miền.
    func toggleTranslation(for tab: BypassBrowserTab) {
        guard let domain = Self.translatableDomain(of: tab.webView.url) else { return }
        let isOn = !tab.isTranslating
        tab.manualTranslate = isOn
        tab.manualTranslateDomain = domain
        clearTranslateHint(of: tab)
        push(isOn, to: tab)
        AppLogger.shared.log("🌐 [BypassBrowser] \(isOn ? "Bật" : "Tắt") dịch QT trang (bấm tay, không ghi nhớ)")
    }

    /// Sau khi đổi công tắc nhớ dịch (bảng khiên): bỏ bật/tắt tay của tab, áp lại theo luật nhớ ngay, không nạp lại trang.
    func reapplyTranslationPolicy(for tab: BypassBrowserTab) {
        tab.manualTranslate = nil
        tab.manualTranslateDomain = nil
        clearTranslateHint(of: tab)
        guard let url = tab.webView.url, Self.translatableDomain(of: url) != nil else {
            tab.setTranslating(false)
            return
        }
        push(Self.policyResolution(for: url).isEnabled, to: tab)
    }

    // MARK: - Điều hướng (gọi từ delegate)

    /// `didCommit` khung chính: tính trạng thái mong muốn cho document mới và đẩy xuống script. Tự bật theo luật nhớ lần
    /// đầu trên tên miền ⇒ đặt dải báo `translateHint`.
    func applyTranslationOnCommit(for webView: WKWebView) {
        guard let tab = tab(for: webView) else { return }
        guard let url = webView.url, let domain = Self.translatableDomain(of: url) else {
            tab.manualTranslate = nil
            tab.manualTranslateDomain = nil
            tab.autoTranslateHintDomain = nil
            clearTranslateHint(of: tab)
            tab.setTranslating(false)
            return
        }
        if tab.manualTranslateDomain != domain {
            tab.manualTranslate = nil
            tab.manualTranslateDomain = nil
        }
        let resolution = Self.policyResolution(for: url)
        let isOn = tab.manualTranslate ?? resolution.isEnabled
        push(isOn, to: tab)
        // Dải báo chỉ ở lần đầu tự dịch trên tên miền này của tab: đọc chương kế tiếp không nháy dải báo mỗi trang.
        if tab.manualTranslate == nil, isOn, let hint = resolution.hintText, tab.autoTranslateHintDomain != domain {
            tab.autoTranslateHintDomain = domain
            tab.translateHint = hint
            AppLogger.shared.log("🌐 [BypassBrowser] Tự dịch QT trang theo luật nhớ")
        } else {
            // Sang tên miền khác ⇒ quên mốc để quay lại tên miền cũ thì báo lại.
            if tab.autoTranslateHintDomain != domain { tab.autoTranslateHintDomain = nil }
            clearTranslateHint(of: tab)
        }
    }

    /// `didFinish`: đẩy lại trạng thái hiện tại (idempotent) — lệnh lúc commit có thể tới document trước khi script dịch
    /// kịp cài, hoặc trang vừa khôi phục từ bộ đệm lùi/tiến.
    func syncTranslationState(of tab: BypassBrowserTab) {
        guard Self.translatableDomain(of: tab.webView.url) != nil else { return }
        push(tab.isTranslating, to: tab)
    }

    // MARK: - Nội bộ

    private func push(_ isOn: Bool, to tab: BypassBrowserTab) {
        let webView = tab.webView
        MainActor.assumeIsolated {
            if isOn {
                BrowserPageTranslator.enable(on: webView)
            } else {
                BrowserPageTranslator.disable(on: webView)
            }
        }
        tab.setTranslating(isOn)
    }

    private func clearTranslateHint(of tab: BypassBrowserTab) {
        if tab.translateHint != nil { tab.translateHint = nil }
    }

    private static func policyResolution(for url: URL) -> BrowserTranslateResolution {
        let urlString = url.absoluteString
        return MainActor.assumeIsolated { BrowserTranslatePolicy.resolve(urlString: urlString) }
    }

    /// Tên miền chuẩn hoá của trang web http(s); Home / `about:blank` / không phải web ⇒ `nil`.
    private static func translatableDomain(of url: URL?) -> String? {
        guard let url, isWebURL(url) else { return nil }
        return BrowserSitePreferenceStore.normalizedDomain(for: url.host)
    }
}
