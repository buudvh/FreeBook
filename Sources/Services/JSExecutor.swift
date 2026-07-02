import Foundation
import JavaScriptCore

public final class JSExecutor {
    public let context: JSContext
    public let localPath: String?
    
    public init(localPath: String? = nil) {
        self.context = JSContext()
        self.localPath = localPath
        
        // 1. Cấu hình Exception Handler
        context.exceptionHandler = { context, exception in
            let desc = exception?.toString() ?? "Unknown Javascript error"
            let line = exception?.objectForKeyedSubscript("line")?.toString() ?? "unknown"
            let column = exception?.objectForKeyedSubscript("column")?.toString() ?? "unknown"
            let stack = exception?.objectForKeyedSubscript("stack")?.toString() ?? "no stacktrace"
            print("❌ JSContext Exception: \(desc) at line \(line), column \(column)")
            print("🥞 JS Stacktrace: \(stack)")
        }
        
        // 2. Đăng ký JSHtml namespace cho JS với tên "Html"
        context.setObject(JSHtml.self, forKeyedSubscript: "Html" as NSCopying & NSObjectProtocol)
        
        // 3. Đăng ký hàm fetch toàn cục
        JSNetwork.registerFetch(in: context)
        
        // 4. Định nghĩa console.log để debug từ tiện ích dễ hơn
        let logBlock: @convention(block) (String) -> Void = { msg in
            print("💬 JS Console: \(msg)")
        }
        
        let console = JSValue(newObjectIn: context)
        console?.setObject(logBlock, forKeyedSubscript: "log" as NSCopying & NSObjectProtocol)
        context.setObject(console, forKeyedSubscript: "console" as NSCopying & NSObjectProtocol)
        
        // 5. Định nghĩa hàm load(filename) để nạp các file thư viện JS khác (libs.js, ...) tương tự Rhino
        let loadBlock: @convention(block) (String) -> Void = { [weak self] filename in
            guard let self = self, let localPath = self.localPath else {
                print("❌ JS Load error: localPath is not set in JSExecutor")
                return
            }
            
            let fileUrl = URL(fileURLWithPath: localPath).appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: fileUrl.path) else {
                print("❌ JS Load error: File not found at path: \(fileUrl.path)")
                return
            }
            
            do {
                let script = try String(contentsOf: fileUrl, encoding: .utf8)
                self.context.evaluateScript(script)
                print("✅ JS Loaded library: \(filename)")
            } catch {
                print("❌ JS Load error running \(filename): \(error.localizedDescription)")
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
        
        // 7. Đăng ký đối tượng Engine toàn cục (mocking Browser)
        let syncFetchBlock: @convention(block) (String) -> String = { urlString in
            print("🌐 [Engine.Browser] Sync Fetching: \(urlString)")
            guard let url = URL(string: urlString) else { return "" }
            var resultHtml = ""
            let semaphore = DispatchSemaphore(value: 0)
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("❌ [Engine.Browser] Fetch error: \(error.localizedDescription)")
                }
                if let data = data {
                    resultHtml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? ""
                }
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 10.0)
            return resultHtml
        }
        context.setObject(syncFetchBlock, forKeyedSubscript: "_nativeSyncFetch" as NSCopying & NSObjectProtocol)
        
        let engineBootstrap = """
        var Engine = {
            newBrowser: function() {
                return {
                    _html: "",
                    launch: function(url, timeout) {
                        console.log("🤖 [Engine.Browser] launch(" + url + ")");
                        this._html = _nativeSyncFetch(url);
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
    }
    
    /// Inject các cấu hình dưới dạng biến toàn cục vào JSContext
    public func injectGlobals(_ globals: [String: Any]) {
        for (key, value) in globals {
            context.setObject(value, forKeyedSubscript: key as NSCopying & NSObjectProtocol)
        }
    }
    
    /// Chạy bất đồng bộ một hàm JS và giải quyết (resolve) Promise nếu cần
    public func runAsync(scriptContent: String, functionName: String, arguments: [Any]) async throws -> JSValue {
        // Thực thi mã nguồn trước để nạp hàm vào context
        context.evaluateScript(scriptContent)
        
        guard let function = context.objectForKeyedSubscript(functionName) else {
            throw NSError(domain: "JSExecutor", code: -404, userInfo: [NSLocalizedDescriptionKey: "JS Function '\(functionName)' not found"])
        }
        
        guard let result = function.call(withArguments: arguments) else {
            throw NSError(domain: "JSExecutor", code: -500, userInfo: [NSLocalizedDescriptionKey: "JS execution returned null"])
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
