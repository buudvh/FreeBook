import UIKit

/// Cửa sổ 1 điểm nằm **dưới** cửa sổ chính, giữ WKWebView ẩn của Gemini Web ở trạng thái "hiển thị"
/// theo cách WebKit hiểu.
///
/// Lỗi thật 1.3.507: WKWebView không nằm trong window nào ⇒ WebKit không giữ assertion cho tiến trình
/// WebContent; khi không còn page load đang chạy, iOS **tạm dừng** tiến trình đó dù app đang foreground
/// và mọi `fetch()` đang bay đứng im — không reject, không chunk, chỉ còn idle timeout
/// (`StreamGenerate timeout … chunk=0` trong khi Google trả header sau ~1 s). `WebViewLoader` bypass
/// Cloudflare không gặp vì luôn có page load đang chạy và poll bằng `evaluateJavaScript`.
///
/// Cửa sổ không nhận chạm, alpha gần 0, level dưới `.normal` nên người dùng không thấy; app vào background
/// thì WebKit vẫn tạm dừng tiến trình — đó là hành vi mong muốn. Mẫu cửa sổ phụ giống widget TTS/AI.
@MainActor
final class GeminiWebHiddenWindowHost {
    private var window: UIWindow?
    private let container = UIViewController()

    /// Gắn (hoặc gắn lại khi scene đổi) view vào cửa sổ; gọi lặp lại vô hại.
    func attach(_ view: UIView) {
        let host = ensureWindow()
        if view.superview !== container.view {
            view.removeFromSuperview()
            container.view.addSubview(view)
        }
        host.isHidden = false
    }

    func detach(_ view: UIView) {
        view.removeFromSuperview()
        window?.isHidden = true
        window = nil
    }

    private func ensureWindow() -> UIWindow {
        let scene = Self.activeWindowScene
        if let window, scene == nil || window.windowScene === scene { return window }
        window?.isHidden = true
        let created: UIWindow = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
        created.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        created.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue - 1)
        created.alpha = 0.02
        created.isUserInteractionEnabled = false
        created.backgroundColor = .clear
        container.view.backgroundColor = .clear
        created.rootViewController = container
        window = created
        return created
    }

    private static var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }
}
