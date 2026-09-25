import Foundation
import WebKit

/// Client điều phối giao tiếp trực tiếp với phiên web ChatGPT (`chatgpt.com`).
///
/// Sử dụng `WKWebView` chạy ngầm chia sẻ `WKWebsiteDataStore.default()` để gửi yêu cầu
/// trong ngữ cảnh phiên duyệt web của người dùng, vượt qua Cloudflare Turnstile và tận dụng
/// hạn ngạch trò chuyện web (không tốn quota API).
public final class ChatGPTWebClient: NSObject, @unchecked Sendable {
    public static let shared = ChatGPTWebClient()

    private var backgroundWebView: WKWebView?
    private let lock = NSLock()
    private var activeStreamContinuations: [String: AsyncThrowingStream<String, Error>.Continuation] = [:]
    private var scriptBridge: ScriptBridge?

    private final class ScriptBridge: NSObject, WKScriptMessageHandler {
        weak var parent: ChatGPTWebClient?

        init(parent: ChatGPTWebClient) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let reqId = dict["requestId"] as? String,
                  let type = dict["type"] as? String else {
                return
            }

            parent?.handleScriptMessage(requestId: reqId, type: type, data: dict)
        }
    }

    private override init() {
        super.init()
    }

    @MainActor
    private func ensureWebView() -> WKWebView {
        if let existing = backgroundWebView {
            return existing
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()

        let bridge = ScriptBridge(parent: self)
        self.scriptBridge = bridge
        config.userContentController.add(bridge, name: "chatGPTWebStream")

        let webView = WKWebView(frame: .zero, configuration: config)
        self.backgroundWebView = webView

        // Nạp trang gốc chatgpt.com để thiết lập origin và session context
        if let url = URL(string: "https://chatgpt.com") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    /// Kiểm tra xem phiên duyệt web hiện tại đã đăng nhập vào `chatgpt.com` hay chưa.
    @MainActor
    public func checkLoginStatus() async -> Bool {
        // 1. Kiểm tra cookie phiên đăng nhập trực tiếp từ CookieStore của WebKit
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }

        let hasSessionCookie = cookies.contains { cookie in
            (cookie.domain.contains("chatgpt.com") || cookie.domain.contains("openai.com")) &&
            (cookie.name.contains("session-token") || cookie.name.contains("session_token") || cookie.name == "accessToken")
        }

        if hasSessionCookie {
            return true
        }

        // 2. Fallback: gọi kiểm tra API session qua callAsyncJavaScript
        let webView = ensureWebView()
        let script = """
        try {
            const res = await fetch('https://chatgpt.com/api/auth/session');
            if (!res.ok) return false;
            const data = await res.json();
            return !!(data && data.accessToken);
        } catch (e) {
            return false;
        }
        """

        let result = try? await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        if let boolVal = result as? Bool {
            return boolVal
        }

        return false
    }

    /// Gửi tin nhắn và nhận stream phản hồi từ ChatGPT Web.
    public func sendChatStreaming(
        model: String,
        messages: [OpenAIChatRequest.Message]
    ) -> AsyncThrowingStream<String, Error> {
        let requestId = UUID().uuidString
        let effectiveModel = model.isEmpty || model == "auto" ? "auto" : model

        // Tổng hợp văn bản prompt từ messages
        let promptText = messages.map { m in
            if m.role == "system" {
                return "[Chỉ thị hệ thống: \(m.content)]"
            }
            return "\(m.role == "user" ? "Người dùng" : "Trợ lý"): \(m.content)"
        }.joined(separator: "\n\n")

        return AsyncThrowingStream { continuation in
            lock.lock()
            activeStreamContinuations[requestId] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.activeStreamContinuations.removeValue(forKey: requestId)
                self?.lock.unlock()
            }

            Task { @MainActor in
                let webView = self.ensureWebView()

                // Đảm bảo webView đã nạp xong context domain chatgpt.com
                if webView.url?.host?.contains("chatgpt.com") != true {
                    if webView.url == nil, let url = URL(string: "https://chatgpt.com") {
                        webView.load(URLRequest(url: url))
                    }
                    var waited = 0
                    while (webView.url?.host?.contains("chatgpt.com") != true) && waited < 10 {
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        waited += 1
                    }
                }

                let escapedPrompt = promptText
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                    .replacingOccurrences(of: "$", with: "\\$")

                let script = """
                (() => {
                    (async () => {
                        const reqId = "\(requestId)";
                        try {
                            const sessionRes = await fetch('/api/auth/session');
                            if (!sessionRes.ok) {
                                window.webkit.messageHandlers.chatGPTWebStream.postMessage({
                                    requestId: reqId,
                                    type: "error",
                                    message: "Chưa đăng nhập ChatGPT Web hoặc phiên hết hạn (HTTP " + sessionRes.status + ")"
                                });
                                return;
                            }
                            const sessionData = await sessionRes.json();
                            const token = sessionData?.accessToken;
                            if (!token) {
                                window.webkit.messageHandlers.chatGPTWebStream.postMessage({
                                    requestId: reqId,
                                    type: "error",
                                    message: "Không tìm thấy phiên đăng nhập ChatGPT hợp lệ"
                                });
                                return;
                            }

                            const payload = {
                                action: "next",
                                messages: [
                                    {
                                        id: crypto.randomUUID(),
                                        author: { role: "user" },
                                        content: {
                                            content_type: "text",
                                            parts: [`\(escapedPrompt)`]
                                        }
                                    }
                                ],
                                parent_message_id: crypto.randomUUID(),
                                model: "\(effectiveModel)",
                                history_and_training_disabled: true
                            };

                            const convRes = await fetch('/backend-api/conversation', {
                                method: 'POST',
                                headers: {
                                    'Authorization': 'Bearer ' + token,
                                    'Content-Type': 'application/json',
                                    'Accept': 'text/event-stream'
                                },
                                body: JSON.stringify(payload)
                            });

                            if (!convRes.ok) {
                                window.webkit.messageHandlers.chatGPTWebStream.postMessage({
                                    requestId: reqId,
                                    type: "error",
                                    message: "Lỗi ChatGPT Web HTTP " + convRes.status
                                });
                                return;
                            }

                            const reader = convRes.body.getReader();
                            const decoder = new TextDecoder();
                            let lastLength = 0;

                            while (true) {
                                const { done, value } = await reader.read();
                                if (done) break;
                                const chunkStr = decoder.decode(value, { stream: true });
                                const lines = chunkStr.split('\\n');
                                for (const line of lines) {
                                    const trimmed = line.trim();
                                    if (!trimmed.startsWith('data:')) continue;
                                    const jsonStr = trimmed.slice(5).trim();
                                    if (jsonStr === '[DONE]') {
                                        window.webkit.messageHandlers.chatGPTWebStream.postMessage({
                                            requestId: reqId,
                                            type: "done"
                                        });
                                        return;
                                    }
                                    try {
                                        const parsed = JSON.parse(jsonStr);
                                        const parts = parsed?.message?.content?.parts;
                                        if (parts && parts.length > 0) {
                                            const fullText = parts[0];
                                            if (fullText.length > lastLength) {
                                                const delta = fullText.slice(lastLength);
                                                lastLength = fullText.length;
                                                window.webkit.messageHandlers.chatGPTWebStream.postMessage({
                                                    requestId: reqId,
                                                    type: "chunk",
                                                    text: delta
                                                });
                                            }
                                        }
                                    } catch (e) {}
                                }
                            }

                            window.webkit.messageHandlers.chatGPTWebStream.postMessage({
                                requestId: reqId,
                                type: "done"
                            });
                        } catch (err) {
                            window.webkit.messageHandlers.chatGPTWebStream.postMessage({
                                requestId: reqId,
                                type: "error",
                                message: err.message || String(err)
                            });
                        }
                    })();
                    return "started";
                })();
                """

                do {
                    _ = try await webView.evaluateJavaScript(script)
                } catch {
                    self.lock.lock()
                    let cont = self.activeStreamContinuations.removeValue(forKey: requestId)
                    self.lock.unlock()
                    cont?.finish(throwing: error)
                }
            }
        }
    }

    /// Gửi tin nhắn một lần (Non-streaming).
    public func sendChat(
        model: String,
        messages: [OpenAIChatRequest.Message]
    ) async throws -> String {
        var fullText = ""
        let stream = sendChatStreaming(model: model, messages: messages)
        for try await chunk in stream {
            fullText += chunk
        }
        return fullText
    }

    fileprivate func handleScriptMessage(requestId: String, type: String, data: [String: Any]) {
        lock.lock()
        let continuation = activeStreamContinuations[requestId]
        lock.unlock()

        guard let cont = continuation else { return }

        switch type {
        case "chunk":
            if let text = data["text"] as? String {
                cont.yield(text)
            }
        case "done":
            lock.lock()
            activeStreamContinuations.removeValue(forKey: requestId)
            lock.unlock()
            cont.finish()
        case "error":
            lock.lock()
            activeStreamContinuations.removeValue(forKey: requestId)
            lock.unlock()
            let msg = data["message"] as? String ?? "Lỗi không xác định từ ChatGPT Web"
            cont.finish(throwing: NSError(domain: "ChatGPTWebClient", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))
        default:
            break
        }
    }
}
