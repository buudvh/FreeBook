import Foundation
import WebKit

/// Đăng nhập Google cho provider Gemini Web bằng **trình duyệt bypass** của app (`VisibleBrowserTabManager`).
///
/// **Lỗi thật 1.3.512 — vì sao không dùng sheet SwiftUI riêng nữa.** Log máy thật: mở đăng nhập từ màn AI trong
/// Reader khi TTS đang đọc thì WKWebView đăng nhập bị **tạo mới 10 lần trong 30 giây** (mỗi nhịp TTS, khi quay lại
/// từ Gmail), mỗi lần nạp lại trang đăng nhập từ đầu ⇒ bước "bấm số" xong quay về nhập email. Không có dòng nào báo
/// iOS giải phóng tiến trình web. Sheet đó nằm đáy chuỗi `ReaderView → fullScreenCover AI → sheet Cài đặt → hàng
/// Form → sheet`, và ReaderView vẽ lại theo từng highlight TTS nên SwiftUI dựng lại cả nhánh. Trình duyệt bypass
/// giữ WebView trong một đối tượng UIKit sống suốt app, nằm ngoài cây SwiftUI ⇒ Reader vẽ lại không chạm tới.
///
/// Nhận biết xong bằng **host** của URL (KVO `webView.url`) chứ không so chuỗi con: URL đăng nhập chứa tham số
/// `continue=…gemini.google.com…` nên so chuỗi con sẽ báo xong ngay từ trang đầu. Cùng `WKWebsiteDataStore.default()`
/// với phiên Gemini Web ẩn nên cookie dùng được ngay.
@MainActor
final class GeminiWebLoginLauncher {
    static let shared = GeminiWebLoginLauncher()

    private static let tabId = "gemini-web-login"
    private static let targetHost = "gemini.google.com"

    private var loader: VisibleWebViewLoader?
    private var urlObservation: NSKeyValueObservation?
    private var onFinished: ((Bool) -> Void)?
    private var finished = false

    private init() {}

    /// Mở (hoặc đưa lên lại) tab đăng nhập. `onFinished(true)` khi đã tới gemini.google.com, `false` khi người
    /// dùng đóng tab trước đó.
    func start(onFinished: @escaping (Bool) -> Void) {
        self.onFinished = onFinished
        if loader != nil {
            VisibleBrowserTabManager.shared.selectTab(id: Self.tabId)
            return
        }

        finished = false
        Task { await GeminiWebClient.shared.prepareForLogin() }

        let loader = VisibleWebViewLoader(id: Self.tabId, title: "Đăng nhập Google")
        loader.onClose = { [weak self] in
            self?.handleClosed()
        }
        urlObservation = loader.viewController.webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            let host = webView.url?.host?.lowercased()
            let path = webView.url?.path ?? ""
            Task { @MainActor in self?.handleURLChange(host: host, path: path) }
        }
        self.loader = loader
        AppLogger.shared.log("🤖 [GeminiWebLogin] Mở đăng nhập trong trình duyệt bypass")

        loader.loadAsync(url: GeminiWebRequestBuilder.loginURL)
        // `loadAsync` thêm tab ở lượt main kế tiếp; `selectTab` xếp sau nó ⇒ luôn mở toàn màn hình, kể cả khi cài
        // đặt "mở trình duyệt ở chế độ thu nhỏ" đang bật (đăng nhập cần người dùng thao tác ngay).
        DispatchQueue.main.async {
            VisibleBrowserTabManager.shared.selectTab(id: Self.tabId)
        }
    }

    /// Chỉ host + path vào log: query của trang Google mang token.
    private func handleURLChange(host: String?, path: String) {
        guard !finished, let host else { return }
        AppLogger.shared.log("🤖 [GeminiWebLogin] Điều hướng: \(host)\(path)")
        guard host == Self.targetHost else { return }

        finished = true
        AppLogger.shared.log("🤖 [GeminiWebLogin] Đã tới gemini.google.com — đăng nhập xong, đóng tab")
        Task { @MainActor in
            await GeminiWebClient.shared.refreshAfterLogin()
            // Chờ Gemini ghi nốt cookie phiên trước khi đóng tab.
            try? await Task.sleep(nanoseconds: 800_000_000)
            VisibleBrowserTabManager.shared.removeTab(id: Self.tabId)
            self.deliver(true)
        }
    }

    /// `onClose` của loader chạy cả khi người dùng đóng tab lẫn khi chính launcher đóng tab sau khi xong.
    private func handleClosed() {
        urlObservation?.invalidate()
        urlObservation = nil
        loader = nil
        guard !finished else { return }
        finished = true
        AppLogger.shared.log("🤖 [GeminiWebLogin] Người dùng đóng trình duyệt trước khi đăng nhập xong")
        deliver(false)
    }

    private func deliver(_ signedIn: Bool) {
        let callback = onFinished
        onFinished = nil
        callback?(signedIn)
    }
}
