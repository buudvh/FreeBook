import Foundation
import WebKit

/// Phía native của dịch trang QT (`BrowserPageTranslateScript`): nhận lô chữ từ handler `fbPageTranslate`, dịch
/// **ngoài main** bằng `TranslateUtils.translateContent(_, bookId: nil)` (từ điển chưa nạp thì hàm đó tự trả nguyên văn)
/// và trả mảng cùng độ dài; cộng các hàm gọi JS trong `BrowserPageTranslateScript.contentWorld`.
///
/// Handler là `MessageHandler` lồng bên trong (proxy **không** giữ chủ): `WKUserContentController` giữ handler bằng
/// tham chiếu mạnh, nên chủ (`BypassBrowserTabStore`) chỉ truyền closure `accepts` tự `[weak self]` để định tuyến theo
/// `message.webView`. Namespace là `enum` để hàm dịch thuần không bị suy luận cô lập actor theo protocol của WebKit.
enum BrowserPageTranslator {
    static let messageHandlerName = "fbPageTranslate"
    /// Trần phía native — rộng hơn trần của script (120 mục / 12 000 ký tự) để lô hợp lệ không bao giờ bị cắt; mục
    /// vượt trần vẫn được trả lời (nguyên văn), không từ chối cả lô.
    static let maxItemsPerBatch = 200
    static let maxCharactersPerBatch = 64_000

    // MARK: - Cài handler

    /// Gỡ handler cùng tên **trong cùng world** trước khi thêm: thêm trùng tên là WebKit ném exception (tab con dùng
    /// chung `WKUserContentController` của tab mẹ). `accepts(webView)` chạy trên main, trả `false` khi webView không
    /// thuộc tab nào đang dịch ⇒ trả nguyên văn.
    static func installMessageHandler(
        into controller: WKUserContentController,
        accepts: @escaping (WKWebView?) -> Bool
    ) {
        let world = BrowserPageTranslateScript.contentWorld
        controller.removeScriptMessageHandler(forName: messageHandlerName, contentWorld: world)
        controller.addScriptMessageHandler(MessageHandler(accepts: accepts), contentWorld: world, name: messageHandlerName)
    }

    // MARK: - Gọi JS (MainActor)

    // `evaluateJavaScript(_:in:in:…)` là overlay Swift của WebKit (cô lập `@MainActor`) nên các hàm gọi JS đều
    // `@MainActor`; store gọi qua `MainActor.assumeIsolated`.

    /// Bật dịch trang đang hiển thị; script chưa sẵn sàng thì xếp hàng. Gọi lặp không sao (idempotent).
    @MainActor
    static func enable(on webView: WKWebView) {
        webView.evaluateJavaScript(
            BrowserPageTranslateScript.enableCall, in: nil, in: BrowserPageTranslateScript.contentWorld, completionHandler: nil
        )
    }

    /// Tắt dịch và khôi phục bản gốc. Gọi trên document mới (chưa dịch) cũng không sao.
    @MainActor
    static func disable(on webView: WKWebView) {
        webView.evaluateJavaScript(
            BrowserPageTranslateScript.disableCall, in: nil, in: BrowserPageTranslateScript.contentWorld, completionHandler: nil
        )
    }

    /// Vùng chọn hiện tại của khung chính; `nil` khi không có chữ được chọn hoặc gọi JS lỗi.
    @MainActor
    static func selectionInfo(in webView: WKWebView) async -> BrowserSelectionInfo? {
        // Bản `async` của overlay (iOS 15+); đoạn JS luôn trả chuỗi JSON nên kết quả không bao giờ rỗng.
        let value = try? await webView.evaluateJavaScript(
            BrowserPageTranslateScript.selectionInfoCall, in: nil, contentWorld: BrowserPageTranslateScript.contentWorld
        )
        guard let json = value as? String, let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = object["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let source = (object["source"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? text
        let link = (object["link"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        return BrowserSelectionInfo(text: text, sourceText: source, linkURL: link)
    }

    // MARK: - Dịch

    /// Dịch từng mục, giữ đúng độ dài và thứ tự. Mục từ vị trí vượt `maxItemsPerBatch`/`maxCharactersPerBatch` trả
    /// nguyên văn (script sẽ bỏ qua vì bản dịch trùng bản gốc). Hàm thuần — gọi từ thread nền.
    static func translate(_ texts: [String]) -> [String] {
        var output: [String] = []
        output.reserveCapacity(texts.count)
        var budget = maxCharactersPerBatch
        for (index, text) in texts.enumerated() {
            let length = text.utf16.count
            guard index < maxItemsPerBatch, length <= budget else {
                output.append(text)
                continue
            }
            budget -= length
            let translated = TranslateUtils.translateContent(text, bookId: nil)
            output.append(translated.isEmpty ? text : translated)
        }
        return output
    }

    /// `body = { texts: [String] }`; phần tử không phải chuỗi ⇒ chuỗi rỗng (giữ độ dài mảng). Sai dạng ⇒ `nil`.
    fileprivate static func texts(from body: Any) -> [String]? {
        guard let dictionary = body as? [String: Any], let raw = dictionary["texts"] as? [Any] else { return nil }
        return raw.map { ($0 as? String) ?? "" }
    }

    // MARK: - Handler

    /// Proxy handler có trả lời. **Luôn** gọi `replyHandler` đúng một lần ở mọi nhánh — WebKit kiểm tra việc này.
    final class MessageHandler: NSObject, WKScriptMessageHandlerWithReply {
        private let accepts: (WKWebView?) -> Bool

        init(accepts: @escaping (WKWebView?) -> Bool) {
            self.accepts = accepts
            super.init()
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage,
            replyHandler: @escaping (Any?, String?) -> Void
        ) {
            guard message.name == BrowserPageTranslator.messageHandlerName,
                  let texts = BrowserPageTranslator.texts(from: message.body) else {
                AppLogger.shared.log("❌ [BrowserTranslate] Lô dịch sai dạng — bỏ qua")
                replyHandler(nil, "invalid")
                return
            }
            guard message.frameInfo.isMainFrame, accepts(message.webView) else {
                // Tab không còn dịch (vừa tắt / đã đóng): trả nguyên văn, script tự bỏ qua.
                replyHandler(texts, nil)
                return
            }
            guard !texts.isEmpty else {
                replyHandler(texts, nil)
                return
            }
            Task { @MainActor in
                let translated = await Task.detached(priority: .userInitiated) {
                    BrowserPageTranslator.translate(texts)
                }.value
                replyHandler(translated, nil)
            }
        }
    }
}
