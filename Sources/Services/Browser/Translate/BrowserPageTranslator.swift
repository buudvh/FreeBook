import Foundation
import WebKit

/// Phía native của xử lý chữ trang (`BrowserPageTranslateScript`): nhận lô chữ từ handler `fbPageTranslate`, xử lý
/// **ngoài main** bằng `ChineseTextPipeline.content` — phồn → giản nếu bật ⇒ dịch QT nếu bật ⇒ trả (từ điển chưa nạp
/// thì bước dịch tự trả nguyên văn) — và trả mảng cùng độ dài; cộng các hàm gọi JS trong
/// `BrowserPageTranslateScript.contentWorld`.
///
/// Hai bước **độc lập** (1.3.846): chỉ bật phồn → giản ⇒ trang hiện giản thể, không dịch. Từ điển chung
/// (`dictionaryBookId: nil`) — trình duyệt không gắn truyện, không theo luật ba cấp của popup dịch.
///
/// Handler là `MessageHandler` lồng bên trong (proxy **không** giữ chủ): `WKUserContentController` giữ handler bằng
/// tham chiếu mạnh, nên chủ (`BypassBrowserTabStore`) chỉ truyền closure `pageOptions` tự `[weak self]` để định tuyến
/// theo `message.webView` — chạy trên main **trước** khi xử lý, trả hai cờ của tab (`nil` = tab không xử lý chữ), chỉ
/// `Options` (Sendable) đi sang thread nền. Namespace là `enum` để hàm xử lý thuần không bị suy luận cô lập actor theo
/// protocol của WebKit.
enum BrowserPageTranslator {
    static let messageHandlerName = "fbPageTranslate"
    /// Trần phía native — rộng hơn trần của script (120 mục / 12 000 ký tự) để lô hợp lệ không bao giờ bị cắt; mục
    /// vượt trần vẫn được trả lời (nguyên văn), không từ chối cả lô.
    static let maxItemsPerBatch = 200
    static let maxCharactersPerBatch = 64_000

    // MARK: - Cài handler

    /// Gỡ handler cùng tên **trong cùng world** trước khi thêm: thêm trùng tên là WebKit ném exception (tab con dùng
    /// chung `WKUserContentController` của tab mẹ). `pageOptions(webView)` chạy trên main, mỗi lô một lần: cách xử lý chữ
    /// của tab (`BypassBrowserTab.pageTextOptions`); `nil` khi webView không thuộc tab nào đang chuyển / dịch ⇒ trả
    /// nguyên văn.
    static func installMessageHandler(
        into controller: WKUserContentController,
        pageOptions: @escaping (WKWebView?) -> ChineseTextPipeline.Options?
    ) {
        let world = BrowserPageTranslateScript.contentWorld
        controller.removeScriptMessageHandler(forName: messageHandlerName, contentWorld: world)
        controller.addScriptMessageHandler(
            MessageHandler(pageOptions: pageOptions),
            contentWorld: world,
            name: messageHandlerName
        )
    }

    // MARK: - Gọi JS (MainActor)

    // `evaluateJavaScript(_:in:in:…)` là overlay Swift của WebKit (cô lập `@MainActor`) nên các hàm gọi JS đều
    // `@MainActor`; store gọi qua `MainActor.assumeIsolated`.

    /// Bật xử lý chữ trang đang hiển thị theo hai cờ; script chưa sẵn sàng thì xếp hàng. Gọi lặp cùng cờ không sao
    /// (idempotent); khác cờ với lượt đang chạy ⇒ script khôi phục bản gốc rồi xử lý lại. Cả hai tắt ⇒ `disable`.
    @MainActor
    static func enable(on webView: WKWebView, translates: Bool, converts: Bool) {
        guard translates || converts else {
            disable(on: webView)
            return
        }
        let mode = (converts ? "c" : "") + (translates ? "t" : "")
        webView.evaluateJavaScript(
            BrowserPageTranslateScript.enableCall(mode: mode), in: nil, in: BrowserPageTranslateScript.contentWorld,
            completionHandler: nil
        )
    }

    /// Tắt xử lý và khôi phục bản gốc. Gọi trên document mới (chưa xử lý) cũng không sao.
    @MainActor
    static func disable(on webView: WKWebView) {
        webView.evaluateJavaScript(
            BrowserPageTranslateScript.disableCall, in: nil, in: BrowserPageTranslateScript.contentWorld, completionHandler: nil
        )
    }

    /// Vùng chọn hiện tại của khung chính; `nil` khi không có chữ được chọn hoặc gọi JS lỗi. `sourceText` là chữ thô của
    /// trang (bản gốc của đoạn đã dịch) — phồn → giản do store áp lúc bấm (`BypassBrowserTabStore+ContextActions`).
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

    // MARK: - Xử lý chữ

    /// Xử lý từng mục (`ChineseTextPipeline.content`: chuyển ⇒ dịch ⇒ trả), giữ đúng độ dài và thứ tự. Mục từ vị trí
    /// vượt `maxItemsPerBatch`/`maxCharactersPerBatch` trả nguyên văn (script sẽ bỏ qua vì chữ trả về trùng bản gốc).
    /// `options` đã tính trên main theo cờ của tab. Hàm thuần — gọi từ thread nền.
    static func process(_ texts: [String], options: ChineseTextPipeline.Options) -> [String] {
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
            let processed = ChineseTextPipeline.content(text, options)
            output.append(processed.isEmpty ? text : processed)
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
        private let pageOptions: (WKWebView?) -> ChineseTextPipeline.Options?

        init(pageOptions: @escaping (WKWebView?) -> ChineseTextPipeline.Options?) {
            self.pageOptions = pageOptions
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
            // Đọc cờ của tab trên main; chỉ `Options` (Sendable) đi sang thread nền.
            guard message.frameInfo.isMainFrame, let options = pageOptions(message.webView) else {
                // Tab không còn chuyển / dịch (vừa tắt / đã đóng): trả nguyên văn, script tự bỏ qua.
                replyHandler(texts, nil)
                return
            }
            guard !texts.isEmpty else {
                replyHandler(texts, nil)
                return
            }
            Task { @MainActor in
                let processed = await Task.detached(priority: .userInitiated) {
                    BrowserPageTranslator.process(texts, options: options)
                }.value
                replyHandler(processed, nil)
            }
        }
    }
}
