import Foundation
import WebKit

/// Xử lý chữ trang của trình duyệt người dùng: cài script/handler (`installBrowserSupport`), áp luật nhớ khi trang
/// commit, nút dịch bấm tay và áp lại sau khi đổi công tắc nhớ.
///
/// **Hai bước độc lập** (1.3.846), mỗi tab giữ hai cờ (`BypassBrowserTab.isConvertingTraditional`, `isTranslating`):
/// - phồn → giản = chỉnh riêng theo tên miền ?? công tắc chung (`BrowserTranslatePolicy.convertsTraditional`) — chạy
///   **cả khi không dịch** (trang hiện giản thể);
/// - dịch QT = bật/tắt **tay** của tab (`manualTranslate`, chỉ khi trang còn cùng tên miền chuẩn hoá lúc bấm) ?? luật
///   nhớ (`BrowserTranslatePolicy.resolve`).
/// Trang được xử lý khi một trong hai bật; handler đọc hai cờ của tab ở mỗi lô (chuyển ⇒ dịch ⇒ trả). Đổi một trong
/// hai ⇒ script khôi phục bản gốc rồi xử lý lại (chế độ của `enable` khác lượt đang chạy); tắt cả hai ⇒ trả nguyên bản.
/// Trang Home / `about:blank` / không phải web ⇒ tắt cả hai và quên bật/tắt tay. Trạng thái được **đẩy cả hai chiều**
/// (bật ⇒ `enable(chế độ)`, tắt ⇒ `disable`) ở commit và lúc tải xong: trang khôi phục từ bộ đệm lùi/tiến giữ nguyên DOM
/// đã xử lý nên không thể chỉ "không bật".
///
/// `BrowserTranslatePolicy` và hàm gọi JS của `BrowserPageTranslator` là `@MainActor`; gọi qua `MainActor.assumeIsolated`
/// (delegate WebKit chạy trên main) để biên dịch được dù store có được suy luận `@MainActor` hay không.
extension BypassBrowserTabStore {
    // MARK: - Cài script + handler

    /// Cài script xử lý chữ + handler `fbPageTranslate` (và phần menu nhấn giữ) vào `controller`, **một lần** mỗi bộ
    /// điều khiển. Bỏ qua chỉ khi controller đã có trong `installedControllers` **và** còn đúng script: `ObjectIdentifier`
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
            pageOptions: { [weak self] webView in
                guard let self, let webView, let tab = self.tab(for: webView) else { return nil }
                return tab.pageTextOptions
            }
        )
        installContextMenuSupport(into: controller)
    }

    // MARK: - API cho View

    /// Công tắc "Dịch trang" của ngăn kéo: bật/tắt dịch cho **tab này**, không ghi nhớ; giữ khi còn cùng tên miền.
    /// Phồn → giản không đổi (tính lại theo luật cho chắc).
    func toggleTranslation(for tab: BypassBrowserTab) {
        guard let url = tab.webView.url, let domain = Self.translatableDomain(of: url) else { return }
        let isOn = !tab.isTranslating
        tab.manualTranslate = isOn
        tab.manualTranslateDomain = domain
        clearTranslateHint(of: tab)
        push(translates: isOn, converts: Self.policyConverts(for: url), to: tab)
        AppLogger.shared.log("🌐 [BypassBrowser] \(isOn ? "Bật" : "Tắt") dịch QT trang (bấm tay, không ghi nhớ)")
    }

    /// Sau khi đổi công tắc nhớ dịch (bảng khiên): bỏ bật/tắt tay của tab, áp lại theo luật nhớ ngay, không nạp lại trang.
    func reapplyTranslationPolicy(for tab: BypassBrowserTab) {
        tab.manualTranslate = nil
        tab.manualTranslateDomain = nil
        clearTranslateHint(of: tab)
        guard let url = tab.webView.url, Self.translatableDomain(of: url) != nil else {
            tab.setPageProcessing(translates: false, converts: false)
            return
        }
        push(translates: Self.policyResolution(for: url).isEnabled, converts: Self.policyConverts(for: url), to: tab)
    }

    // MARK: - Phồn → giản (1.3.684, bước riêng từ 1.3.846)

    /// Sau khi đổi chỉnh riêng phồn → giản của `hosts` (bảng khiên): áp lại cờ cho **mọi** tab web thuộc các tên miền
    /// đó hoặc tên miền con của chúng (tra chỉnh riêng gộp tên miền cha) — kể cả tab không dịch (bật ⇒ trang bắt đầu
    /// hiện giản thể, tắt ⇒ trả nguyên bản). Không đụng bật/tắt tay hay luật nhớ tự dịch.
    func reapplyConvertPolicy(underHosts hosts: [String]) {
        let domains = hosts.compactMap { BrowserSitePreferenceStore.normalizedDomain(for: $0) }
        guard !domains.isEmpty else { return }
        reapplyConvertPolicy(where: { domain in
            domains.contains { domain == $0 || domain.hasSuffix("." + $0) }
        })
    }

    /// Sau khi đổi công tắc chung phồn → giản (Cài đặt › Trình duyệt): áp lại cho tab web **không** có chỉnh riêng phồn →
    /// giản theo tên miền (tab có chỉnh riêng giữ nguyên cờ).
    func reapplyConvertPolicyFollowingGlobal() {
        reapplyConvertPolicy(where: { domain in
            BrowserSitePreferenceStore.shared.preference(forHost: domain)?.convertsTraditional == nil
        })
    }

    /// Tính lại cờ phồn → giản của tab web mà `isAffected(tên miền chuẩn hoá)`; cờ đổi ⇒ đẩy xuống script (khôi phục bản
    /// gốc rồi xử lý lại theo chế độ mới, hoặc trả nguyên bản khi cả hai tắt). Không nạp lại trang, giữ cờ dịch; lô đang
    /// bay của lượt cũ bị script bỏ (đổi `generation`).
    private func reapplyConvertPolicy(where isAffected: (String) -> Bool) {
        var count = 0
        for tab in tabs {
            guard let url = tab.webView.url, let domain = Self.translatableDomain(of: url), isAffected(domain) else {
                continue
            }
            let converts = Self.policyConverts(for: url)
            guard converts != tab.isConvertingTraditional else { continue }
            push(translates: tab.isTranslating, converts: converts, to: tab)
            count += 1
        }
        if count > 0 {
            AppLogger.shared.log("🌐 [BypassBrowser] Áp lại phồn → giản cho \(count) tab")
        }
    }

    // MARK: - Điều hướng (gọi từ delegate)

    /// `didCommit` khung chính: tính hai cờ cho document mới và đẩy xuống script. Tự **dịch** theo luật nhớ lần đầu trên
    /// tên miền ⇒ đặt dải báo `translateHint` (chỉ phồn → giản thì không báo: cờ đó theo công tắc chung, báo ở mọi tên
    /// miền mới là ồn).
    func applyTranslationOnCommit(for webView: WKWebView) {
        guard let tab = tab(for: webView) else { return }
        guard let url = webView.url, let domain = Self.translatableDomain(of: url) else {
            tab.manualTranslate = nil
            tab.manualTranslateDomain = nil
            tab.autoTranslateHintDomain = nil
            clearTranslateHint(of: tab)
            tab.setPageProcessing(translates: false, converts: false)
            return
        }
        if tab.manualTranslateDomain != domain {
            tab.manualTranslate = nil
            tab.manualTranslateDomain = nil
        }
        let resolution = Self.policyResolution(for: url)
        let isOn = tab.manualTranslate ?? resolution.isEnabled
        push(translates: isOn, converts: Self.policyConverts(for: url), to: tab)
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

    /// `didFinish`: đẩy lại trạng thái hiện tại (idempotent — cùng chế độ thì script bỏ qua) — lệnh lúc commit có thể tới
    /// document trước khi script kịp cài, hoặc trang vừa khôi phục từ bộ đệm lùi/tiến.
    func syncTranslationState(of tab: BypassBrowserTab) {
        guard Self.translatableDomain(of: tab.webView.url) != nil else { return }
        push(translates: tab.isTranslating, converts: tab.isConvertingTraditional, to: tab)
    }

    // MARK: - Nội bộ

    /// Ghi hai cờ lên tab **trước** khi gọi JS: lô đầu tiên của lượt mới (handler đọc cờ trên main) dùng cờ mới.
    private func push(translates: Bool, converts: Bool, to tab: BypassBrowserTab) {
        tab.setPageProcessing(translates: translates, converts: converts)
        let webView = tab.webView
        MainActor.assumeIsolated {
            BrowserPageTranslator.enable(on: webView, translates: translates, converts: converts)
        }
    }

    private func clearTranslateHint(of tab: BypassBrowserTab) {
        if tab.translateHint != nil { tab.translateHint = nil }
    }

    private static func policyResolution(for url: URL) -> BrowserTranslateResolution {
        let urlString = url.absoluteString
        return MainActor.assumeIsolated { BrowserTranslatePolicy.resolve(urlString: urlString) }
    }

    private static func policyConverts(for url: URL) -> Bool {
        let urlString = url.absoluteString
        return MainActor.assumeIsolated { BrowserTranslatePolicy.convertsTraditional(urlString: urlString) }
    }

    /// Tên miền chuẩn hoá của trang web http(s); Home / `about:blank` / không phải web ⇒ `nil`.
    private static func translatableDomain(of url: URL?) -> String? {
        guard let url, isWebURL(url) else { return nil }
        return BrowserSitePreferenceStore.normalizedDomain(for: url.host)
    }
}
