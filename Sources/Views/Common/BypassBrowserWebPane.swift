import SwiftUI
import UIKit
import WebKit

/// Khung hiển thị `WKWebView` của tab đang chọn.
///
/// Dùng một `UIView` container trung gian nên đổi tab chỉ là đổi subview: mỗi
/// `WKWebView` giữ nguyên lịch sử điều hướng và vị trí cuộn của tab đó.
///
/// Thanh kính dưới của trình duyệt nổi **đè** lên trang (mockup 2026-10-30) ⇒ `bottomObstruction` = chiều cao phần đáy
/// khung này bị thanh che (đo từ mép dưới khung). Container đặt `contentInset.bottom` + thụt thanh cuộn của web view sao
/// cho **tổng** thụt đáy (gồm phần hệ thống tự cộng, vd safe area vạch Home) bằng đúng con số đó — nội dung cuối trang
/// cuộn lên được phía trên thanh. Áp lại mỗi lần đổi tab (web view khác), đổi số đo, hoặc safe area đổi.
struct BypassBrowserWebPane: UIViewRepresentable {
    let webView: WKWebView
    var bottomObstruction: CGFloat = 0

    func makeUIView(context: Context) -> Container {
        let container = Container()
        container.backgroundColor = .systemBackground
        container.bottomObstruction = bottomObstruction
        container.embed(webView)
        return container
    }

    func updateUIView(_ uiView: Container, context: Context) {
        uiView.bottomObstruction = bottomObstruction
        if webView.superview !== uiView {
            uiView.embed(webView)
        }
        uiView.applyBottomInset()
    }

    final class Container: UIView {
        var bottomObstruction: CGFloat = 0 {
            didSet {
                if oldValue != bottomObstruction { setNeedsLayout() }
            }
        }

        private weak var webView: WKWebView?

        func embed(_ webView: WKWebView) {
            for subview in subviews where subview !== webView {
                subview.removeFromSuperview()
            }
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(webView)
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: topAnchor),
                webView.leadingAnchor.constraint(equalTo: leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: trailingAnchor),
                webView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            self.webView = webView
            applyBottomInset()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyBottomInset()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            setNeedsLayout()
        }

        /// Phần hệ thống tự cộng = `adjustedContentInset - contentInset` (không đổi khi ta đổi `contentInset`) ⇒ không
        /// có vòng lặp, và không cộng trùng safe area dù WebKit có tự thụt theo vạch Home hay không.
        func applyBottomInset() {
            guard let scrollView = webView?.scrollView else { return }
            let systemInset = max(0, scrollView.adjustedContentInset.bottom - scrollView.contentInset.bottom)
            let inset = max(0, bottomObstruction - systemInset)
            if scrollView.contentInset.bottom != inset {
                scrollView.contentInset.bottom = inset
            }
            if scrollView.verticalScrollIndicatorInsets.bottom != inset {
                scrollView.verticalScrollIndicatorInsets.bottom = inset
            }
        }
    }
}
