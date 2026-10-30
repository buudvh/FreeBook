import Foundation
import UIKit
import WebKit

/// Menu nhấn giữ của trình duyệt người dùng: script nhấn giữ link/ảnh + chọn chữ (`BrowserContextMenuScript`, cài vào
/// `BrowserPageTranslateScript.contentWorld`), handler proxy yếu định tuyến theo `message.webView` ⇒ `tab(for:)`, và
/// menu nhấn giữ link (`WKUIDelegate`).
///
/// Được `installBrowserSupport(into:)` gọi **một lần** cho mỗi `WKUserContentController` (tab con dùng chung bộ điều
/// khiển của tab mẹ). Phòng khi bị gọi lại trên cùng bộ điều khiển: script chỉ thêm khi chưa có (so nguồn) và tự chặn
/// chạy lại bằng cờ `window.__fbContextMenuInstalled`; handler cùng tên trong cùng world được gỡ trước khi thêm.
///
/// Delegate WebKit có thể không được suy luận `@MainActor` ⇒ thân của chúng chạy qua `MainActor.assumeIsolated`
/// (WebKit gọi delegate trên main), phần còn lại là hàm `@MainActor`.
extension BypassBrowserTabStore {
    func installContextMenuSupport(into controller: WKUserContentController) {
        if !BrowserContextMenuScript.isInstalled(in: controller) {
            controller.addUserScript(BrowserContextMenuScript.userScript())
        }
        BrowserContextMenuBridge.installMessageHandler(into: controller) { [weak self] message, webView in
            self?.handleContextMenuMessage(message, from: webView)
        }
    }

    // MARK: - Message của script

    @MainActor
    private func handleContextMenuMessage(_ message: BrowserContextMenuMessage, from webView: WKWebView) {
        guard let browserView = webView as? BrowserWebView, tab(for: webView) != nil else { return }
        switch message {
        case let .selection(text, linkURL, sourceHasHan):
            browserView.updateSelection(text: text, linkURL: linkURL, sourceHasHan: sourceHasHan)
        case let .touch(imageURL, linkURL):
            browserView.recordImageTouch(imageURL: imageURL, linkURL: linkURL)
        case let .imageHold(imageURL, pagePoint):
            browserView.presentImageMenu(imageURL: imageURL, pagePoint: pagePoint)
        }
    }

    // MARK: - WKUIDelegate: nhấn giữ link

    /// Menu nhấn giữ link: không xem trước trang (`previewProvider: nil` — WebKit nhấc chính phần tử link lên), tiêu
    /// đề = URL. Không phải link http(s) (`mailto:`, `tel:`, `javascript:`…) ⇒ `nil` (WebKit tự xử lý). Gọi
    /// `completionHandler` đúng một lần ở mọi nhánh.
    func webView(
        _ webView: WKWebView,
        contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping (UIContextMenuConfiguration?) -> Void
    ) {
        guard let url = elementInfo.linkURL, Self.isWebURL(url) else {
            completionHandler(nil)
            return
        }
        MainActor.assumeIsolated {
            let menu = self.makeLinkMenu(url: url, webView: webView)
            completionHandler(UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu })
        }
    }

    /// Chạm vào phần tử đang nhấc lên ⇒ mở link ngay trên tab này.
    func webView(
        _ webView: WKWebView,
        contextMenuForElement elementInfo: WKContextMenuElementInfo,
        willCommitWithAnimator animator: UIContextMenuInteractionCommitAnimating
    ) {
        guard let url = elementInfo.linkURL, Self.isWebURL(url) else { return }
        animator.addCompletion { [weak self, weak webView] in
            guard let webView else { return }
            MainActor.assumeIsolated {
                self?.openInCurrentTab(url, webView: webView)
            }
        }
    }

    // MARK: - Dựng menu

    /// Mở · Mở trong tab mới · Mở trong tab nền | Sao chép link · Chia sẻ… | (link bọc ảnh) "Ảnh": Lưu ảnh · Sao chép ảnh.
    @MainActor
    private func makeLinkMenu(url: URL, webView: WKWebView) -> UIMenu {
        let open = BrowserWebView.menuAction("Mở", image: UIImage(systemName: "arrow.up.right")) { [weak self, weak webView] in
            guard let webView else { return }
            self?.openInCurrentTab(url, webView: webView)
        }
        let newTab = BrowserWebView.menuAction(
            "Mở trong tab mới", image: UIImage(systemName: "plus.square.on.square")
        ) { [weak self, weak webView] in
            guard let webView else { return }
            self?.openInNewTab(url, from: webView, activate: true)
        }
        let backgroundTab = BrowserWebView.menuAction(
            "Mở trong tab nền", image: UIImage(systemName: "square.on.square")
        ) { [weak self, weak webView] in
            guard let webView else { return }
            self?.openInNewTab(url, from: webView, activate: false)
        }
        let copyLink = BrowserWebView.menuAction("Sao chép link", image: UIImage(systemName: "link")) {
            UIPasteboard.general.url = url
            ToastManager.shared.show(message: "Đã sao chép link", type: .success)
        }
        let share = BrowserWebView.menuAction(
            "Chia sẻ…", image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak self] in
            self?.requestShare(url: url)
        }
        var sections: [UIMenuElement] = [
            UIMenu(title: "", options: .displayInline, children: [open, newTab, backgroundTab]),
            UIMenu(title: "", options: .displayInline, children: [copyLink, share])
        ]
        if let imageURL = (webView as? BrowserWebView)?.imageURL(forLinkMenu: url) {
            let imageActions = imageMenuActions(for: imageURL, in: webView, includesOpenInNewTab: false)
            if !imageActions.isEmpty {
                sections.append(UIMenu(title: "Ảnh", options: .displayInline, children: imageActions))
            }
        }
        return UIMenu(title: url.absoluteString, children: sections)
    }

    /// Nhóm "Ảnh": Lưu ảnh · Sao chép ảnh (+ Mở ảnh trong tab mới cho menu ảnh ngoài link, chỉ ảnh http(s)).
    @MainActor
    func imageMenuActions(for imageURL: URL, in webView: WKWebView, includesOpenInNewTab: Bool) -> [UIMenuElement] {
        let copyImage = UIImage(named: AppGlyph.copy.assetName)?.withRenderingMode(.alwaysTemplate)
        var actions: [UIMenuElement] = []
        if BrowserImageFetcher.isSupported(imageURL) {
            actions.append(BrowserWebView.menuAction(
                "Lưu ảnh", image: UIImage(systemName: "arrow.down.to.line")
            ) { [weak self, weak webView] in
                guard let webView else { return }
                self?.performImageAction(.save, imageURL: imageURL, in: webView)
            })
            actions.append(BrowserWebView.menuAction("Sao chép ảnh", image: copyImage) { [weak self, weak webView] in
                guard let webView else { return }
                self?.performImageAction(.copy, imageURL: imageURL, in: webView)
            })
        }
        if includesOpenInNewTab, Self.isWebURL(imageURL) {
            actions.append(BrowserWebView.menuAction(
                "Mở ảnh trong tab mới", image: UIImage(systemName: "plus.square.on.square")
            ) { [weak self, weak webView] in
                guard let webView else { return }
                self?.performImageAction(.openInNewTab, imageURL: imageURL, in: webView)
            })
        }
        return actions
    }
}
