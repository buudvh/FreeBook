import SwiftUI
import UIKit
import WebKit

/// Khung hiển thị `WKWebView` của tab đang chọn.
///
/// Dùng một `UIView` container trung gian nên đổi tab chỉ là đổi subview: mỗi
/// `WKWebView` giữ nguyên lịch sử điều hướng và vị trí cuộn của tab đó.
struct BypassBrowserWebPane: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .systemBackground
        embed(webView, in: container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard webView.superview !== uiView else { return }
        for subview in uiView.subviews where subview !== webView {
            subview.removeFromSuperview()
        }
        embed(webView, in: uiView)
    }

    private func embed(_ webView: WKWebView, in container: UIView) {
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}
