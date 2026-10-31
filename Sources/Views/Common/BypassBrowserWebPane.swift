import SwiftUI
import UIKit
import WebKit

/// Khung hiển thị `WKWebView` của tab đang chọn.
///
/// Dùng một `UIView` container trung gian nên đổi tab chỉ là đổi subview: mỗi
/// `WKWebView` giữ nguyên lịch sử điều hướng và vị trí cuộn của tab đó.
///
/// Thanh dưới của trình duyệt gắn sát đáy, nằm **ngoài** khung này (2026-10-31) ⇒ không còn phần nào của trang bị che,
/// không cần thụt `contentInset` đáy như hồi thanh nổi đè lên trang.
struct BypassBrowserWebPane: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> Container {
        let container = Container()
        container.backgroundColor = .systemBackground
        container.embed(webView)
        return container
    }

    func updateUIView(_ uiView: Container, context: Context) {
        if webView.superview !== uiView {
            uiView.embed(webView)
        }
    }

    final class Container: UIView {
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
        }
    }
}
