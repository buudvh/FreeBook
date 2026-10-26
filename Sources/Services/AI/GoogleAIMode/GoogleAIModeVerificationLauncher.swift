import Foundation

/// Mở trang Chế độ AI của Google trong **trình duyệt bypass** của app để người dùng giải captcha (1.3.609).
///
/// Cùng `WKWebsiteDataStore.default()` với WebView ẩn của Chế độ AI ⇒ giải xong là cookie miễn kiểm tra có hiệu lực ngay
/// cho lượt sau. Không tự bật — chỉ mở khi người dùng bấm "Mở Google để xác minh" (người dùng chọn). Giữ `loader` tới
/// khi tab đóng (loader bị giải phóng là tab tự dọn); bấm lại khi tab còn mở thì chỉ đưa tab lên.
@MainActor
final class GoogleAIModeVerificationLauncher {
    static let shared = GoogleAIModeVerificationLauncher()

    private static let tabId = "google-ai-mode-verify"

    private var loader: VisibleWebViewLoader?

    private init() {}

    func open() {
        if loader != nil {
            VisibleBrowserTabManager.shared.selectTab(id: Self.tabId)
            return
        }
        let loader = VisibleWebViewLoader(id: Self.tabId, title: "Xác minh Google")
        loader.onClose = { [weak self] in
            self?.loader = nil
            AppLogger.shared.log("🤖 [AIMode] Đóng trang xác minh Google")
        }
        self.loader = loader
        AppLogger.shared.log("🤖 [AIMode] Mở trang xác minh Google trong trình duyệt bypass")
        loader.loadAsync(url: GoogleAIModePageContract.verificationURL)
        // `loadAsync` thêm tab ở lượt main kế tiếp; `selectTab` xếp sau nó ⇒ luôn mở toàn màn hình.
        DispatchQueue.main.async {
            VisibleBrowserTabManager.shared.selectTab(id: Self.tabId)
        }
    }
}
