import Foundation
import WebKit

/// Phía native của script menu nhấn giữ (`BrowserContextMenuScript`): cài handler `fbContextMenu` và gọi JS lấy ngữ
/// cảnh vùng chọn cho sheet Tra từ điển.
///
/// Handler là `MessageHandler` lồng bên trong — proxy **không** giữ chủ (`WKUserContentController` giữ handler bằng
/// tham chiếu mạnh); chủ (`BypassBrowserTabStore`) truyền closure tự `[weak self]` và định tuyến theo `message.webView`.
enum BrowserContextMenuBridge {
    // MARK: - Cài handler

    /// Gỡ handler cùng tên **trong cùng world** trước khi thêm: thêm trùng tên là WebKit ném exception (tab con dùng
    /// chung `WKUserContentController` của tab mẹ). `onMessage` chạy trên main, chỉ nhận message của khung chính đã
    /// đọc được (`BrowserContextMenuMessage`).
    static func installMessageHandler(
        into controller: WKUserContentController,
        onMessage: @escaping @MainActor (BrowserContextMenuMessage, WKWebView) -> Void
    ) {
        let world = BrowserPageTranslateScript.contentWorld
        let name = BrowserContextMenuScript.messageHandlerName
        controller.removeScriptMessageHandler(forName: name, contentWorld: world)
        // `add(_:contentWorld:name:)` là bản **không** trả lời; `addScriptMessageHandler(_:contentWorld:name:)` đòi
        // `WKScriptMessageHandlerWithReply` (chỉ handler dịch trang dùng bản đó).
        controller.add(MessageHandler(onMessage: onMessage), contentWorld: world, name: name)
    }

    // MARK: - Gọi JS (MainActor)

    /// Ngữ cảnh vùng chọn hiện tại cho sheet Tra từ điển; `nil` khi không có vùng chọn hoặc gọi JS lỗi.
    @MainActor
    static func lookupRequest(in webView: WKWebView) async -> BrowserLookupRequest? {
        let value = try? await webView.evaluateJavaScript(
            BrowserContextMenuScript.selectionContextCall, in: nil, contentWorld: BrowserPageTranslateScript.contentWorld
        )
        guard let json = value as? String, let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let context = object["text"] as? String,
              !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let word = (object["word"] as? String) ?? ""
        let offset = (object["offset"] as? NSNumber)?.intValue ?? -1
        return BrowserLookupRequest(context: context, word: word, wordOffset: offset >= 0 ? offset : nil)
    }

    /// `navigator.userAgent` của trang (gửi kèm khi tải ảnh); lỗi ⇒ `nil`.
    @MainActor
    static func userAgent(of webView: WKWebView) async -> String? {
        if let custom = webView.customUserAgent, !custom.isEmpty { return custom }
        let value = try? await webView.evaluateJavaScript(
            "String(navigator.userAgent || \"\")", in: nil, contentWorld: BrowserPageTranslateScript.contentWorld
        )
        guard let agent = value as? String, !agent.isEmpty else { return nil }
        return agent
    }

    // MARK: - Handler

    /// Proxy handler không trả lời. Bỏ message của khung con (script chỉ cài ở khung chính, phòng hờ) và message sai
    /// dạng; webView đã giải phóng ⇒ bỏ.
    final class MessageHandler: NSObject, WKScriptMessageHandler {
        private let onMessage: @MainActor (BrowserContextMenuMessage, WKWebView) -> Void

        init(onMessage: @escaping @MainActor (BrowserContextMenuMessage, WKWebView) -> Void) {
            self.onMessage = onMessage
            super.init()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == BrowserContextMenuScript.messageHandlerName,
                  message.frameInfo.isMainFrame,
                  let webView = message.webView else { return }
            guard let parsed = BrowserContextMenuMessage(body: message.body) else {
                AppLogger.shared.log("❌ [BrowserContextMenu] Message sai dạng — bỏ qua")
                return
            }
            let handler = onMessage
            // WebKit gọi handler trên main.
            MainActor.assumeIsolated {
                handler(parsed, webView)
            }
        }
    }
}
