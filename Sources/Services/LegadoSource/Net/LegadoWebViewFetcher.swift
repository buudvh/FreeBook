import Foundation
import WebKit

/// Tải trang bằng WebView ẩn cho option `webView: true` và `java.webView` (spec §4.4), dựa trên `WebViewLoader` sẵn có.
///
/// Luồng: thread engine xếp việc sang main **bất đồng bộ** rồi chờ semaphore theo lát ngắn (có kiểm huỷ) — không bao giờ
/// chờ trên main. Trên main: đẩy cookie của nguồn vào kho cookie WebKit → nạp `URLRequest` (giữ header, phương thức, thân) →
/// chờ trang tải xong (tự hết giờ như `WebViewLoader.load`) → chờ thêm `webViewDelayTime` → chạy `webJs` nếu có (giá trị
/// `null` thì thử lại tối đa 3 lần, mỗi lần cách 1 giây), không thì lấy `outerHTML` → đọc lại cookie của tên miền.
enum LegadoWebViewFetcher {
    struct Result {
        var body: String
        var finalURL: String
        var cookies: [HTTPCookie]
    }

    private final class State: @unchecked Sendable {
        var loader: WebViewLoader?
        var result: Result?
        var finished = false
        var failureMessage: String?
    }

    private static let webJsRetryLimit = 3

    /// `htmlString` khác `nil` ⇒ nạp chuỗi HTML đó với URL nền `request.url` (`java.webView(html, url, js)`).
    /// `sourceRegex` khác `nil` (spec §9.4): không lấy HTML khi trang tải xong mà theo dõi mọi URL trang request (điều
    /// hướng, XHR, fetch, media — `WebViewLoader` đã cài bộ bắt request); URL đầu tiên khớp **toàn chuỗi** thành thân.
    /// Hết `timeout` mà không khớp ⇒ lỗi "không bắt được tài nguyên".
    static func load(request: URLRequest, htmlString: String? = nil, userAgent: String, delay: TimeInterval,
                     webJs: String?, timeout: TimeInterval, cookies: [HTTPCookie],
                     cancellation: LegadoEngineCancellation, sourceRegex: NSRegularExpression? = nil) throws -> Result {
        let state = State()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            start(state, request: request, htmlString: htmlString, userAgent: userAgent, delay: delay, webJs: webJs,
                  timeout: timeout, cookies: cookies, sourceRegex: sourceRegex, semaphore: semaphore)
        }
        let handlerId = cancellation.register {
            DispatchQueue.main.async { complete(state, result: nil, semaphore: semaphore) }
        }
        defer { cancellation.unregister(handlerId) }

        let finished = try cancellation.wait(semaphore, timeout: timeout + delay + Double(webJsRetryLimit) + 10)
        guard finished else {
            DispatchQueue.main.async { complete(state, result: nil, semaphore: semaphore) }
            throw URLError(.timedOut)
        }
        try cancellation.check()
        guard let result = state.result else {
            if let message = state.failureMessage {
                throw LegadoEngineError.network(url: request.url?.absoluteString ?? "", message: message)
            }
            throw URLError(.cannotLoadFromNetwork)
        }
        return result
    }

    // MARK: - Main thread
    //
    // Mọi hàm dưới đây chỉ chạy trên main (được gọi từ `DispatchQueue.main` hoặc completion của WebKit); thao tác
    // WebKit/`WebViewLoader` bọc trong `MainActor.assumeIsolated` để rõ ràng về cô lập.

    private static func start(_ state: State, request: URLRequest, htmlString: String?, userAgent: String,
                              delay: TimeInterval, webJs: String?, timeout: TimeInterval, cookies: [HTTPCookie],
                              sourceRegex: NSRegularExpression?, semaphore: DispatchSemaphore) {
        MainActor.assumeIsolated {
            guard !state.finished else { return }
            let loader = WebViewLoader(extensionLocalPath: nil)
            loader.webView.customUserAgent = userAgent
            state.loader = loader
            let cookieStore = loader.webView.configuration.websiteDataStore.httpCookieStore
            setCookies(cookies, into: cookieStore) { [weak loader] in
                guard let loader, !state.finished else { return }
                if let sourceRegex {
                    launchCapturing(loader, state: state, request: request, htmlString: htmlString, pattern: sourceRegex,
                                    timeout: timeout, semaphore: semaphore)
                } else {
                    launch(loader, state: state, request: request, htmlString: htmlString, delay: delay, webJs: webJs,
                           timeout: timeout, semaphore: semaphore)
                }
            }
        }
    }

    private static func launch(_ loader: WebViewLoader, state: State, request: URLRequest, htmlString: String?,
                               delay: TimeInterval, webJs: String?, timeout: TimeInterval, semaphore: DispatchSemaphore) {
        MainActor.assumeIsolated {
            loader.completion = { [weak loader] html in
                guard let loader else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) {
                    let script = webJs?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if script.isEmpty {
                        finish(state, loader: loader, body: html ?? "", request: request, semaphore: semaphore)
                    } else {
                        runWebJs(script, attempt: 0, state: state, loader: loader, request: request, semaphore: semaphore)
                    }
                }
            }
            if let htmlString {
                _ = loader.webView.loadHTMLString(htmlString, baseURL: request.url)
            } else {
                loader.beginLaunch(request)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak loader] in
                guard let loader else { return }
                MainActor.assumeIsolated {
                    guard let pending = loader.completion else { return }
                    loader.completion = nil
                    loader.webView.evaluateJavaScript("document.documentElement.outerHTML") { value, _ in
                        pending(value as? String ?? "")
                    }
                }
            }
        }
    }

    /// Nạp trang rồi dò URL tài nguyên khớp `pattern` mỗi 0,25 giây (main thread).
    private static func launchCapturing(_ loader: WebViewLoader, state: State, request: URLRequest, htmlString: String?,
                                        pattern: NSRegularExpression, timeout: TimeInterval, semaphore: DispatchSemaphore) {
        MainActor.assumeIsolated {
            loader.completion = nil
            if let htmlString {
                _ = loader.webView.loadHTMLString(htmlString, baseURL: request.url)
            } else {
                loader.beginLaunch(request)
            }
        }
        pollResource(loader, state: state, request: request, pattern: pattern,
                     deadline: Date().addingTimeInterval(timeout), semaphore: semaphore)
    }

    private static func pollResource(_ loader: WebViewLoader, state: State, request: URLRequest,
                                     pattern: NSRegularExpression, deadline: Date, semaphore: DispatchSemaphore) {
        guard !state.finished else { return }
        let found: String? = MainActor.assumeIsolated {
            loader.allRequestedUrls.first { matchesWhole(pattern, $0) }
        }
        if let found {
            finish(state, loader: loader, body: found, request: request, semaphore: semaphore)
            return
        }
        if Date() >= deadline {
            state.failureMessage = "Không bắt được tài nguyên khớp sourceRegex"
            complete(state, result: nil, semaphore: semaphore)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            pollResource(loader, state: state, request: request, pattern: pattern, deadline: deadline, semaphore: semaphore)
        }
    }

    /// Khớp **toàn chuỗi** (regex kiểu `.*\.m3u8.*` cho cùng kết quả với khớp một phần).
    static func matchesWhole(_ pattern: NSRegularExpression, _ text: String) -> Bool {
        let length = (text as NSString).length
        guard let match = pattern.firstMatch(in: text, options: [.anchored], range: NSRange(location: 0, length: length)) else {
            return false
        }
        return match.range.location == 0 && match.range.length == length
    }

    private static func setCookies(_ cookies: [HTTPCookie], into store: WKHTTPCookieStore, then next: @escaping () -> Void) {
        guard let first = cookies.first else {
            next()
            return
        }
        let rest = Array(cookies.dropFirst())
        MainActor.assumeIsolated {
            store.setCookie(first) {
                setCookies(rest, into: store, then: next)
            }
        }
    }

    private static func runWebJs(_ script: String, attempt: Int, state: State, loader: WebViewLoader,
                                 request: URLRequest, semaphore: DispatchSemaphore) {
        guard !state.finished else { return }
        MainActor.assumeIsolated {
            loader.webView.evaluateJavaScript(script) { value, _ in
                let text = stringify(value)
                if text == nil, attempt + 1 < webJsRetryLimit {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        runWebJs(script, attempt: attempt + 1, state: state, loader: loader, request: request,
                                 semaphore: semaphore)
                    }
                    return
                }
                finish(state, loader: loader, body: text ?? "", request: request, semaphore: semaphore)
            }
        }
    }

    private static func finish(_ state: State, loader: WebViewLoader, body: String, request: URLRequest,
                               semaphore: DispatchSemaphore) {
        guard !state.finished else { return }
        MainActor.assumeIsolated {
            let pageURL = loader.webView.url ?? request.url
            let finalURL = pageURL?.absoluteString ?? ""
            let host = pageURL?.host?.lowercased() ?? ""
            loader.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { all in
                let related = all.filter { cookie -> Bool in
                    var domain = cookie.domain.lowercased()
                    if domain.hasPrefix(".") { domain.removeFirst() }
                    return !host.isEmpty && (host == domain || host.hasSuffix("." + domain))
                }
                complete(state, result: Result(body: body, finalURL: finalURL, cookies: related), semaphore: semaphore)
            }
        }
    }

    private static func complete(_ state: State, result: Result?, semaphore: DispatchSemaphore) {
        guard !state.finished else { return }
        state.finished = true
        state.result = result
        let loader = state.loader
        state.loader = nil
        if let loader {
            MainActor.assumeIsolated { loader.cleanUp() }
        }
        semaphore.signal()
    }

    /// Giá trị `evaluateJavaScript` → chuỗi; `nil`/`null` ⇒ `nil` (để thử lại).
    private static func stringify(_ value: Any?) -> String? {
        switch value {
        case nil: return nil
        case is NSNull: return nil
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        case let other?:
            if JSONSerialization.isValidJSONObject(other),
               let data = try? JSONSerialization.data(withJSONObject: other),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            return String(describing: other)
        }
    }
}
