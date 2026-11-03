import Foundation
import WebKit

/// Dịch trang QT của trình duyệt người dùng: cài script/handler (`installBrowserSupport`), áp luật nhớ khi trang commit,
/// nút dịch bấm tay và áp lại sau khi đổi công tắc nhớ; dịch lại tab đang dịch khi đổi công tắc phồn → giản (1.3.684 —
/// cờ phồn → giản do handler đọc theo URL trang ở mỗi lô, `BrowserTranslatePolicy.convertsTraditional`).
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
        BrowserPageTranslator.installMessageHandler(
            into: controller,
            accepts: { [weak self] webView in
                guard let self, let webView, let tab = self.tab(for: webView) else { return false }
                return tab.isTranslating
            },
            convertsTraditional: { webView in
                // Handler WebKit chạy trên main; luật là `@MainActor`.
                MainActor.assumeIsolated {
                    guard let urlString = webView?.url?.absoluteString else { return false }
                    return BrowserTranslatePolicy.convertsTraditional(urlString: urlString)
                }
            }
        )
        installContextMenuSupport(into: controller)
    }

    // MARK: - API cho View

    /// Công tắc "Dịch trang" của ngăn kéo: bật/tắt cho **tab này**, không ghi nhớ; giữ khi còn cùng tên miền.
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

    // MARK: - Phồn → giản (1.3.684)

    /// Sau khi đổi chỉnh riêng phồn → giản của `hosts` (bảng khiên): dịch lại tab đang dịch thuộc các tên miền đó hoặc
    /// tên miền con của chúng (tra chỉnh riêng gộp tên miền cha). Không đụng bật/tắt tay hay luật nhớ tự dịch.
    func retranslateTabs(underHosts hosts: [String]) {
        let domains = hosts.compactMap { BrowserSitePreferenceStore.normalizedDomain(for: $0) }
        guard !domains.isEmpty else { return }
        retranslateTabs(where: { domain in
            domains.contains { domain == $0 || domain.hasSuffix("." + $0) }
        })
    }

    /// Sau khi đổi công tắc chung phồn → giản (Cài đặt › Trình duyệt): dịch lại tab đang dịch **không** có chỉnh riêng
    /// phồn → giản theo tên miền (tab có chỉnh riêng giữ nguyên cờ nên khỏi dịch lại).
    func retranslateTabsFollowingGlobalConvert() {
        retranslateTabs(where: { domain in
            BrowserSitePreferenceStore.shared.preference(forHost: domain)?.convertsTraditional == nil
        })
    }

    /// Tắt rồi bật lại dịch trang trên tab **đang dịch** mà `isAffected(tên miền chuẩn hoá)`: script khôi phục bản gốc
    /// theo node rồi quét lại, nên chữ được gửi dịch lần nữa và handler đọc cờ mới. Không nạp lại trang, không đổi
    /// `isTranslating`; lô đang bay của lượt cũ bị script bỏ (đổi `generation`).
    private func retranslateTabs(where isAffected: (String) -> Bool) {
        var count = 0
        for tab in tabs where tab.isTranslating {
            guard let domain = Self.translatableDomain(of: tab.webView.url), isAffected(domain) else { continue }
            let webView = tab.webView
            MainActor.assumeIsolated {
                BrowserPageTranslator.disable(on: webView)
                BrowserPageTranslator.enable(on: webView)
            }
            count += 1
        }
        if count > 0 {
            AppLogger.shared.log("🌐 [BypassBrowser] Dịch lại \(count) tab sau khi đổi phồn → giản")
        }
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
