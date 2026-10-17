import Foundation
import WebKit

/// Browser ẩn của ext loại **video** (`Engine.newBrowser()`): WKWebView không nằm trong window nào thì WebKit không giữ
/// assertion cho tiến trình WebContent — iOS có thể tạm dừng nó và chặn phát media dù đã bật autoplay (cùng lỗi mà
/// `VideoMediaSniffer` và Gemini Web đã gặp, xem `GeminiWebHiddenWindowHost`). Gắn webView vào cửa sổ ẩn khi tạo,
/// gỡ khi `cleanUp`/`deinit`. Ext khác không đi qua đây (giữ WKWebView khung 0, ngoài window như cũ).
extension WebViewLoader {
    /// Khung cỡ màn iPhone: WebKit coi view 0×0 là không hiển thị và có thể không phát media.
    static let mediaFrame = CGRect(x: 0, y: 0, width: 390, height: 844)

    /// Gọi từ `init` — `JSExecutor` luôn tạo loader trên main thread (`main.sync` khi đang ở luồng JS).
    func attachToHiddenWindow() {
        guard Thread.isMainThread else {
            AppLogger.shared.log("❌ [WebViewLoader] Tạo browser video ngoài main thread ⇒ không gắn được cửa sổ ẩn")
            return
        }
        let view = webView
        let host = MainActor.assumeIsolated { GeminiWebHiddenWindowHost() }
        MainActor.assumeIsolated { host.attach(view) }
        hiddenWindowHost = host
    }

    /// Gỡ webView khỏi cửa sổ ẩn; gọi lặp lại vô hại, gọi từ luồng nào cũng được.
    func detachFromHiddenWindow() {
        guard let host = hiddenWindowHost else { return }
        hiddenWindowHost = nil
        WebViewLoader.detach(webView, from: host)
    }

    /// Không chụp `self` để dùng được trong `deinit`.
    static func detach(_ view: WKWebView, from host: GeminiWebHiddenWindowHost) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { host.detach(view) }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { host.detach(view) }
            }
        }
    }
}
