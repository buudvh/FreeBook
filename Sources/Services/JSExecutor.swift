import Foundation
import JavaScriptCore
import WebKit

public final class JSExecutor {
    public let context: JSContext
    public let localPath: String?
    public let downloadUrl: String?
    
    public init(localPath: String? = nil, downloadUrl: String? = nil) {
        self.context = JSContext()
        self.localPath = localPath
        self.downloadUrl = downloadUrl
        
        // 1. Cấu hình Exception Handler
        context.exceptionHandler = { context, exception in
            let desc = exception?.toString() ?? "Unknown Javascript error"
            let line = exception?.objectForKeyedSubscript("line")?.toString() ?? "unknown"
            let column = exception?.objectForKeyedSubscript("column")?.toString() ?? "unknown"
            let stack = exception?.objectForKeyedSubscript("stack")?.toString() ?? "no stacktrace"
            AppLogger.shared.log("❌ JSContext Exception: \(desc) at line \(line), column \(column)")
            AppLogger.shared.log("🥞 JS Stacktrace: \(stack)")
        }
        
        // 2. Đăng ký JSHtml namespace cho JS với tên "Html"
        context.setObject(JSHtml.self, forKeyedSubscript: "Html" as NSCopying & NSObjectProtocol)
        
        // 3. Đăng ký hàm fetch toàn cục
        JSNetwork.registerFetch(in: context)
        
        // 4. Định nghĩa console.log để debug từ tiện ích dễ hơn
        let logBlock: @convention(block) (String) -> Void = { msg in
            AppLogger.shared.log("💬 JS Console: \(msg)")
        }
        
        let console = JSValue(newObjectIn: context)
        console?.setObject(logBlock, forKeyedSubscript: "log" as NSCopying & NSObjectProtocol)
        context.setObject(console, forKeyedSubscript: "console" as NSCopying & NSObjectProtocol)
        
        // 5. Định nghĩa hàm load(filename) để nạp các file thư viện JS khác (libs.js, ...) tương tự Rhino
        let loadBlock: @convention(block) (String) -> Void = { [weak self] filename in
            guard let self = self, let localPath = self.localPath else {
                AppLogger.shared.log("❌ JS Load error: localPath is not set in JSExecutor")
                return
            }
            
            let extUrl = URL(fileURLWithPath: localPath)
            var fileUrl = extUrl.appendingPathComponent(filename)
            var exists = FileManager.default.fileExists(atPath: fileUrl.path)
            
            if !exists {
                let srcFileUrl = extUrl.appendingPathComponent("src").appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: srcFileUrl.path) {
                    fileUrl = srcFileUrl
                    exists = true
                }
            }
            
            if !exists {
                AppLogger.shared.log("❌ JS Load error: File '\(filename)' not found in extension.")
                return
            }
            
            do {
                let data = try Data(contentsOf: fileUrl)
                let script = self.decodeData(data)
                self.context.evaluateScript(script)
                AppLogger.shared.log("✅ JS Loaded library: \(filename)")
            } catch {
                AppLogger.shared.log("❌ JS Load error running \(filename): \(error.localizedDescription)")
            }
        }
        context.setObject(loadBlock, forKeyedSubscript: "load" as NSCopying & NSObjectProtocol)
        
        // 6. Đăng ký đối tượng Response toàn cục
        let responseBootstrap = """
        var Response = {
            success: function(data, hasNext) {
                return data;
            },
            error: function(message) {
                throw new Error(message);
            }
        };
        """
        context.evaluateScript(responseBootstrap)
        
        let syncFetchBlock: @convention(block) (String) -> [String: Any] = { [weak self] urlString in
            guard let self = self else {
                return ["html": "", "status": 500, "raw": ""]
            }
            let resolvedUrlString = self.cleanAndResolveUrl(urlString)
            AppLogger.shared.log("🌐 [JSExecutor] Sync Fetching: \(resolvedUrlString)")
            guard let url = URL(string: resolvedUrlString) else {
                return ["html": "", "status": 400, "raw": ""]
            }
            var resultHtml = ""
            var resultRawBase64 = ""
            var statusCode = 200
            let semaphore = DispatchSemaphore(value: 0)
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    AppLogger.shared.log("❌ [JSExecutor] Fetch error: \(error.localizedDescription)")
                    statusCode = 500
                }
                if let httpResponse = response as? HTTPURLResponse {
                    statusCode = httpResponse.statusCode
                }
                if let data = data {
                    resultHtml = self.decodeData(data)
                    resultRawBase64 = data.base64EncodedString()
                }
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 10.0)
            
            return ["html": resultHtml, "status": statusCode, "raw": resultRawBase64]
        }
        context.setObject(syncFetchBlock, forKeyedSubscript: "_nativeSyncFetch" as NSCopying & NSObjectProtocol)
        
        // Đăng ký hàm decode base64 native hỗ trợ tùy chọn bảng mã
        let decodeBase64Block: @convention(block) (String, String) -> String = { base64Str, encodingName in
            guard let data = Data(base64Encoded: base64Str) else { return "" }
            
            let name = encodingName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            var encoding: String.Encoding = .utf8
            
            if name == "gbk" || name == "gb2312" || name == "gb18030" || name == "euc-cn" || name == "euccn" {
                let rawValue = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
                encoding = String.Encoding(rawValue: rawValue)
            } else if name == "big5" || name == "big-5" || name == "euc-tw" || name == "euctw" {
                let rawValue = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
                encoding = String.Encoding(rawValue: rawValue)
            } else if name == "utf-16" || name == "utf16" {
                encoding = .utf16
            } else if name == "iso-8859-1" || name == "latin1" {
                encoding = .isoLatin1
            } else if name == "ascii" {
                encoding = .ascii
            }
            
            return String(data: data, encoding: encoding) ?? ""
        }
        context.setObject(decodeBase64Block, forKeyedSubscript: "_nativeDecodeBase64" as NSCopying & NSObjectProtocol)
        
        // 8. Đăng ký fetch đồng bộ ghi đè fetch Promise mặc định
        let fetchBootstrap = """
        var fetch = function(url, options) {
            var res = _nativeSyncFetch(url);
            return {
                ok: res.status >= 200 && res.status < 300,
                status: res.status,
                html: function(encoding) {
                    var htmlText = "";
                    if (encoding && res.raw) {
                        htmlText = _nativeDecodeBase64(res.raw, encoding);
                    } else {
                        htmlText = res.html || "";
                    }
                    return Html.parse(htmlText);
                },
                text: function(encoding) {
                    if (encoding && res.raw) {
                        return _nativeDecodeBase64(res.raw, encoding);
                    }
                    return res.html || "";
                },
                json: function() {
                    return JSON.parse(res.html || "{}");
                }
            };
        };
        
        var crawler = {
            get: function(url) {
                return fetch(url);
            }
        };
        """
        context.evaluateScript(fetchBootstrap)
        
        // Đăng ký block chạy browser thực tế bằng WKWebView
        let browserLaunchBlock: @convention(block) (String, Double) -> String = { [weak self] urlString, timeoutMs in
            guard let self = self else { return "" }
            let resolvedUrlString = self.cleanAndResolveUrl(urlString)
            AppLogger.shared.log("🤖 [JSExecutor.Browser] Launching WKWebView for: \(resolvedUrlString)")
            guard let url = URL(string: resolvedUrlString) else { return "" }
            
            let semaphore = DispatchSemaphore(value: 0)
            var resultHtml = ""
            
            DispatchQueue.main.async {
                let loader = WebViewLoader()
                objc_setAssociatedObject(self, UnsafeRawPointer(bitPattern: loader.hash)!, loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                
                loader.load(url: url, timeout: timeoutMs / 1000.0) { html in
                    resultHtml = html ?? ""
                    objc_setAssociatedObject(self, UnsafeRawPointer(bitPattern: loader.hash)!, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                    semaphore.signal()
                }
            }
            
            _ = semaphore.wait(timeout: .now() + (timeoutMs / 1000.0) + 1.0)
            return resultHtml
        }
        context.setObject(browserLaunchBlock, forKeyedSubscript: "_nativeBrowserLaunch" as NSCopying & NSObjectProtocol)
        
        // 9. Đăng ký đối tượng Engine toàn cục (mocking Browser)
        let engineBootstrap = """
        var Engine = {
            newBrowser: function() {
                return {
                    _html: "",
                    launch: function(url, timeout) {
                        console.log("🤖 [Engine.Browser] launch(" + url + ")");
                        this._html = _nativeBrowserLaunch(url, timeout || 5000);
                        return Html.parse(this._html);
                    },
                    html: function() {
                        return Html.parse(this._html || "");
                    },
                    close: function() {
                        console.log("🤖 [Engine.Browser] close()");
                    },
                    setUserAgent: function(ua) {
                        console.log("🤖 [Engine.Browser] setUserAgent(" + ua + ")");
                    },
                    callJs: function(script, waitTime) {
                        console.log("🤖 [Engine.Browser] callJs()");
                        return null;
                    },
                    waitUrl: function(url, timeout) {
                        console.log("🤖 [Engine.Browser] waitUrl()");
                        return true;
                    }
                };
            }
        };
        """
        context.evaluateScript(engineBootstrap)
        
        // 10. Định nghĩa prototype helper cho JSElements (length, forEach)
        let domPrototypeBootstrap = """
        (function() {
            var doc = Html.parse("<html></html>");
            var elms = doc.select("a");
            if (elms && elms.constructor) {
                var Proto = elms.constructor.prototype;
                Object.defineProperty(Proto, 'length', {
                    get: function() { return this.size(); },
                    configurable: true,
                    enumerable: true
                });
                Proto.forEach = function(callback) {
                    var len = this.size();
                    for (var i = 0; i < len; i++) {
                        callback(this.get(i), i, this);
                    }
                };
            }
        })();
        """
        context.evaluateScript(domPrototypeBootstrap)
    }
    
    private func decodeData(_ data: Data) -> String {
        if let utf8Str = String(data: data, encoding: .utf8) {
            return utf8Str
        }
        
        let gbkRawValue = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        let gbkEncoding = String.Encoding(rawValue: gbkRawValue)
        if let gbkStr = String(data: data, encoding: gbkEncoding) {
            return gbkStr
        }
        
        let big5RawValue = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
        let big5Encoding = String.Encoding(rawValue: big5RawValue)
        if let big5Str = String(data: data, encoding: big5Encoding) {
            return big5Str
        }
        
        if let utf16Str = String(data: data, encoding: .utf16) {
            return utf16Str
        }
        
        if let isoStr = String(data: data, encoding: .isoLatin1) {
            return isoStr
        }
        
        if let winStr = String(data: data, encoding: .windowsCP1252) {
            return winStr
        }
        
        if let asciiStr = String(data: data, encoding: .ascii) {
            return asciiStr
        }
        
        return ""
    }
    
    private func cleanAndResolveUrl(_ urlString: String) -> String {
        var cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Nếu chứa nhiều hơn 1 http:// hoặc https://, lấy cái cuối cùng
        let patterns = ["https://", "http://"]
        var lastIndex: String.Index? = nil
        
        for pattern in patterns {
            var searchRange = cleaned.startIndex..<cleaned.endIndex
            while let range = cleaned.range(of: pattern, options: .backwards, range: searchRange) {
                if lastIndex == nil || range.lowerBound > lastIndex! {
                    lastIndex = range.lowerBound
                }
                searchRange = cleaned.startIndex..<range.lowerBound
            }
        }
        
        if let idx = lastIndex, idx != cleaned.startIndex {
            cleaned = String(cleaned[idx...])
            AppLogger.shared.log("⚠️ [JSExecutor] Cleaned duplicate hosts URL to: \(cleaned)")
        }
        
        // 2. Nếu là URL tương đối (không bắt đầu bằng http:// hoặc https://)
        if !cleaned.lowercased().hasPrefix("http://") && !cleaned.lowercased().hasPrefix("https://") {
            // Đọc BASE_URL từ config của extension
            if let localPath = self.localPath {
                let extUrl = URL(fileURLWithPath: localPath)
                let pluginJsonUrl = extUrl.appendingPathComponent("plugin.json")
                if let data = try? Data(contentsOf: pluginJsonUrl),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let configSection = json["config"] as? [String: [String: Any]],
                   let baseUrlConfig = configSection["BASE_URL"],
                   let defaultValue = baseUrlConfig["default"] as? String {
                    
                    let baseUrl = defaultValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    let separator = cleaned.hasPrefix("/") || baseUrl.hasSuffix("/") ? "" : "/"
                    cleaned = baseUrl + separator + cleaned
                    AppLogger.shared.log("🌐 [JSExecutor] Resolved relative URL to: \(cleaned)")
                }
            }
        }
        
        return cleaned
    }
    
    /// Inject các cấu hình dưới dạng biến toàn cục vào JSContext
    public func injectGlobals(_ globals: [String: Any]) {
        for (key, value) in globals {
            context.setObject(value, forKeyedSubscript: key as NSCopying & NSObjectProtocol)
        }
    }
    
    public func runAsync(scriptContent: String, functionName: String, arguments: [Any]) async throws -> JSValue {
        // Reset exception trước khi chạy
        context.exception = nil
        
        // Thực thi mã nguồn trước để nạp hàm vào context
        context.evaluateScript(scriptContent)
        
        // Kiểm tra xem evaluateScript có ném lỗi không
        if let exception = context.exception {
            let desc = exception.toString() ?? "JS Compile Exception"
            context.exception = nil
            throw NSError(domain: "JSExecutor", code: -501, userInfo: [NSLocalizedDescriptionKey: "JS Compile error: \(desc)"])
        }
        
        guard let function = context.objectForKeyedSubscript(functionName) else {
            throw NSError(domain: "JSExecutor", code: -404, userInfo: [NSLocalizedDescriptionKey: "JS Function '\(functionName)' not found"])
        }
        
        guard let result = function.call(withArguments: arguments) else {
            if let exception = context.exception {
                let desc = exception.toString() ?? "JS Execution Exception"
                context.exception = nil
                throw NSError(domain: "JSExecutor", code: -502, userInfo: [NSLocalizedDescriptionKey: "JS Call error: \(desc)"])
            }
            throw NSError(domain: "JSExecutor", code: -500, userInfo: [NSLocalizedDescriptionKey: "JS execution returned null"])
        }
        
        // Kiểm tra xem call có ném lỗi không (nếu trả về JSValue nhưng vẫn ném lỗi bên trong)
        if let exception = context.exception {
            let desc = exception.toString() ?? "JS Execution Exception"
            context.exception = nil
            throw NSError(domain: "JSExecutor", code: -502, userInfo: [NSLocalizedDescriptionKey: "JS Call error: \(desc)"])
        }
        
        // Kiểm tra xem kết quả trả về có phải là Promise (thenable) không
        guard let thenFunc = result.objectForKeyedSubscript("then"),
              !thenFunc.isUndefined,
              thenFunc.isObject else {
            // Trả về kết quả đồng bộ trực tiếp
            return result
        }
        
        // Giải quyết Promise bất đồng bộ
        return try await withCheckedThrowingContinuation { continuation in
            let onResolve: @convention(block) (JSValue) -> Void = { value in
                continuation.resume(returning: value)
            }
            
            let onReject: @convention(block) (JSValue) -> Void = { error in
                let desc = error.toString() ?? "JS Promise rejected"
                continuation.resume(throwing: NSError(domain: "JSExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: desc]))
            }
            
            result.invokeMethod("then", withArguments: [
                JSValue(object: onResolve, in: self.context) as Any,
                JSValue(object: onReject, in: self.context) as Any
            ])
        }
    }
}

// MARK: - WKWebView Headless Browser Loader Helper
class WebViewLoader: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var completion: ((String?) -> Void)?
    
    override init() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all
        
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        self.webView.navigationDelegate = self
        self.webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    }
    
    func load(url: URL, timeout: TimeInterval, completion: @escaping (String?) -> Void) {
        self.completion = completion
        let request = URLRequest(url: url)
        
        DispatchQueue.main.async {
            self.webView.load(request)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self, let comp = self.completion else { return }
            self.completion = nil
            self.webView.evaluateJavaScript("document.documentElement.outerHTML") { html, error in
                comp(html as? String ?? "")
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let comp = self.completion else { return }
        self.completion = nil
        
        webView.evaluateJavaScript("document.documentElement.outerHTML") { html, error in
            comp(html as? String ?? "")
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard let comp = self.completion else { return }
        self.completion = nil
        comp("")
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard let comp = self.completion else { return }
        self.completion = nil
        comp("")
    }
}
