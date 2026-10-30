import UIKit
import WebKit

/// Menu ảnh **không** nằm trong link (Lưu ảnh, Sao chép ảnh, Mở ảnh trong tab mới), bật tại điểm chạm bằng
/// `UIEditMenuInteraction` gắn trên `BrowserWebView`. WebKit không gọi `contextMenuConfigurationForElement` cho ảnh đã
/// tắt callout, nên script tự phát hiện nhấn giữ và báo về (`BrowserContextMenuScript`).
///
/// Delegate là đối tượng riêng (giữ webView yếu) thay vì chính `WKWebView` để không đụng các conformance riêng của
/// WebKit; interaction chỉ gắn lần đầu cần dùng.
@MainActor
final class BrowserImageMenuPresenter: NSObject, UIEditMenuInteractionDelegate {
    private weak var webView: BrowserWebView?
    private var interaction: UIEditMenuInteraction?
    private var imageURL: URL?

    init(webView: BrowserWebView) {
        self.webView = webView
        super.init()
    }

    func present(imageURL: URL, at point: CGPoint) {
        guard let webView, webView.window != nil else { return }
        self.imageURL = imageURL
        let interaction: UIEditMenuInteraction
        if let existing = self.interaction {
            interaction = existing
        } else {
            interaction = UIEditMenuInteraction(delegate: self)
            webView.addInteraction(interaction)
            self.interaction = interaction
        }
        interaction.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
    }

    // MARK: - UIEditMenuInteractionDelegate

    /// Bỏ qua `suggestedActions` (mục sửa chuẩn của chuỗi responder): menu này chỉ có thao tác ảnh.
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        guard let imageURL, let webView,
              let store = webView.uiDelegate as? BypassBrowserTabStore else { return nil }
        let actions = store.imageMenuActions(for: imageURL, in: webView, includesOpenInNewTab: true)
        return actions.isEmpty ? nil : UIMenu(children: actions)
    }
}
