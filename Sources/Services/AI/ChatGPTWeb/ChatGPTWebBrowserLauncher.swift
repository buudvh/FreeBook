import Foundation

/// Mở trang ChatGPT trong **trình duyệt bypass** của app (1.3.971) để người dùng tự làm việc trang đang đòi: đăng nhập
/// ChatGPT, qua bước kiểm tra của Cloudflare, xem thông báo hết lượt.
///
/// Cùng `WKWebsiteDataStore.default()` và cùng UA với WebView ẩn của ChatGPT Web ⇒ đăng nhập / qua bước kiểm tra ở đây là
/// có hiệu lực ngay cho lượt sau. Không tự bật — chỉ mở khi người dùng bấm. Giữ `loader` tới khi tab đóng; bấm lại khi
/// tab còn mở thì chỉ đưa tab lên. `onClose` chạy khi tab đóng (hàng tài khoản đọc lại trạng thái đăng nhập).
@MainActor
final class ChatGPTWebBrowserLauncher {
    static let shared = ChatGPTWebBrowserLauncher()

    private static let tabId = "chatgpt-web-open"

    private var loader: VisibleWebViewLoader?
    private var onClose: (() -> Void)?

    private init() {}

    func open(onClose: (() -> Void)? = nil) {
        if let onClose { self.onClose = onClose }
        if loader != nil {
            VisibleBrowserTabManager.shared.selectTab(id: Self.tabId)
            return
        }
        let loader = VisibleWebViewLoader(id: Self.tabId, title: "ChatGPT")
        loader.onClose = { [weak self] in
            self?.loader = nil
            AppLogger.shared.log("🤖 [ChatGPTWeb] Đóng trang ChatGPT trong trình duyệt bypass")
            let callback = self?.onClose
            self?.onClose = nil
            callback?()
        }
        self.loader = loader
        AppLogger.shared.log("🤖 [ChatGPTWeb] Mở trang ChatGPT trong trình duyệt bypass")
        loader.loadAsync(url: ChatGPTWebPageContract.browserURL)
        // `loadAsync` thêm tab ở lượt main kế tiếp; `selectTab` xếp sau nó ⇒ luôn mở toàn màn hình.
        DispatchQueue.main.async {
            VisibleBrowserTabManager.shared.selectTab(id: Self.tabId)
        }
    }
}
