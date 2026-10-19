import Foundation
import WebKit

/// Áp một `WebContentDecision` lên `WKWebView`: rule list chặn quảng cáo + User-Agent. Chế độ hiển thị
/// (`preferredContentMode`) thì caller đặt trong `decidePolicyFor navigationAction:preferences:` bằng
/// `contentMode(for:)` — WebKit chỉ nhận nó theo từng lượt điều hướng.
///
/// **Không** đánh dấu `@MainActor` để gọi được từ type không cô lập (`WebViewLoader`, `VideoMediaSniffer`…), nhưng
/// bắt buộc chạy trên main thread (đụng `WKWebView`) — `dispatchPrecondition` dừng app (cả bản release) nếu gọi sai luồng.
///
/// Luật/UA mới có hiệu lực từ **lượt nạp trang kế tiếp**; caller tự quyết có nạp lại hay không bằng cách so
/// `WebContentAppliedState` trả về với trạng thái đã áp trước đó.
enum WebContentConfigurator {
    /// Gỡ hết rule list rồi gắn `AdBlockRuleListProvider.currentRuleLists()` nếu `decision.adBlock`;
    /// `customUserAgent = explicitUserAgent ?? (desktop ? .desktop : .mobile)`. UA tiện ích tự khai thắng chế độ
    /// máy tính. Trả trạng thái đã áp.
    @discardableResult
    static func apply(
        _ decision: WebContentDecision,
        to webView: WKWebView,
        explicitUserAgent: String? = nil
    ) -> WebContentAppliedState {
        dispatchPrecondition(condition: .onQueue(.main))
        let applied = state(for: decision, explicitUserAgent: explicitUserAgent)
        // `configuration` trả bản sao cấu hình nhưng `userContentController` vẫn là đúng instance của webview.
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        if decision.adBlock {
            for list in AdBlockRuleListProvider.currentRuleLists() {
                controller.add(list)
            }
        }
        if webView.customUserAgent != applied.userAgent {
            webView.customUserAgent = applied.userAgent
        }
        return applied
    }

    /// Trạng thái sẽ áp cho `decision` — không đụng webview (gọi được từ thread bất kỳ).
    /// UA tự khai rỗng/chỉ khoảng trắng coi như không khai.
    static func state(for decision: WebContentDecision, explicitUserAgent: String? = nil) -> WebContentAppliedState {
        let explicit = explicitUserAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
        let userAgent: String
        if let explicit, !explicit.isEmpty {
            userAgent = explicit
        } else {
            userAgent = decision.desktop ? WebUserAgent.desktop : WebUserAgent.mobile
        }
        return WebContentAppliedState(adBlock: decision.adBlock, userAgent: userAgent, desktop: decision.desktop)
    }

    /// Giá trị cho `WKWebpagePreferences.preferredContentMode`. Không ở chế độ máy tính thì giữ `.recommended` như
    /// trước khi có tính năng này (iPhone = mobile; không đổi hành vi trên iPad).
    static func contentMode(for decision: WebContentDecision) -> WKWebpagePreferences.ContentMode {
        decision.desktop ? .desktop : .recommended
    }
}
