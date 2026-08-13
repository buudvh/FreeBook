import Foundation
import JavaScriptCore
import WebKit

public final class JSExecutor: @unchecked Sendable {
    public let context: JSContext
    public let localPath: String?
    public let downloadUrl: String?
    internal var activeBrowsers: [String: WebViewLoader] = [:]
    internal var activeVisibleBrowsers: [String: VisibleWebViewLoader] = [:]
    internal let networkTaskLock = NSLock()
    internal var activeNetworkTasks: [Int: URLSessionDataTask] = [:]
    internal var nextNetworkTaskID = 0
    internal var executionCancelled = false

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

        // 3. Đăng ký hàm fetch toàn cục (đã được ghi đè bằng sync fetch ở dưới)

        // 4. Định nghĩa console.log để debug từ tiện ích dễ hơn
        let logBlock: @convention(block) () -> Void = {
            let args = JSContext.currentArguments() ?? []

            let message = args.map { item in
                guard let arg = item as? JSValue else {
                    return String(describing: item)
                }

                if arg.isObject {
                    if !arg.isNull && !arg.isUndefined {
                        if let jsonModule = arg.context?.objectForKeyedSubscript("JSON"),
                        let stringifyFunc = jsonModule.objectForKeyedSubscript("stringify"),
                        let result = stringifyFunc.call(withArguments: [arg]),
                        let resultStr = result.toString(),
                        resultStr != "undefined" {
                            return resultStr
                        }
                    }
                }

                return arg.toString() ?? "undefined"
            }
            .joined(separator: " ")

            AppLogger.shared.log("💬 JS Console: \(message)")
        }

        let console = JSValue(newObjectIn: context)
        console?.setObject(logBlock, forKeyedSubscript: "log" as NSCopying & NSObjectProtocol)
        context.setObject(console, forKeyedSubscript: "console" as NSCopying & NSObjectProtocol)
        context.setObject(console, forKeyedSubscript: "Console" as NSCopying & NSObjectProtocol)

        // Đăng ký atob và btoa chuẩn Web
        let atobBlock: @convention(block) (String) -> String = { base64Str in
            guard let data = Data(base64Encoded: base64Str) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }
        context.setObject(atobBlock, forKeyedSubscript: "atob" as NSCopying & NSObjectProtocol)

        let btoaBlock: @convention(block) (String) -> String = { str in
            guard let data = str.data(using: .utf8) else { return "" }
            return data.base64EncodedString()
        }
        context.setObject(btoaBlock, forKeyedSubscript: "btoa" as NSCopying & NSObjectProtocol)

        // 5. Định nghĩa hàm load(filename) để nạp các file thư viện JS khác (libs.js, ...) tương tự Rhino
        let loadBlock: @convention(block) (String) -> Void = { [weak self] filename in
            guard let self = self, let localPath = self.localPath else {
                // AppLogger.shared.log("❌ JS Load error: localPath is not set in JSExecutor")
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
                // AppLogger.shared.log("❌ JS Load error: File '\(filename)' not found in extension.")
                return
            }

            do {
                let data = try Data(contentsOf: fileUrl)
                let script = self.decodeData(data)
                self.context.evaluateScript(script)
                // AppLogger.shared.log("✅ JS Loaded library: \(filename)")
            } catch {
                // AppLogger.shared.log("❌ JS Load error running \(filename): \(error.localizedDescription)")
            }
        }
        context.setObject(loadBlock, forKeyedSubscript: "load" as NSCopying & NSObjectProtocol)

        // 6. Đăng ký đối tượng Response toàn cục
        let responseBootstrap = """
        var Response = {
            nextPage: null,
            success: function(data, hasNext) {
                Response.nextPage = hasNext || null;
                return {
                    success: true,
                    data: data,
                    next: hasNext || null
                };
            },
            error: function(message) {
                return {
                    success: false,
                    message: message || "Lỗi không xác định từ nguồn truyện"
                };
            }
        };
        """
        context.evaluateScript(responseBootstrap)

        // 6.5. Đăng ký đối tượng UserAgent toàn cục
        let userAgentBootstrap = """
        var UserAgent = {
            android: function() { return "Mozilla/5.0 (Linux; Android 13; SM-S901B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36"; },
            ios: function() { return "Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1"; },
            pc: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.0.0 Safari/537.36"; },
            computer: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.0.0 Safari/537.36"; }
        };
        """
        context.evaluateScript(userAgentBootstrap)

        // 6.6. Đăng ký đối tượng Script toàn cục (hỗ trợ thực thi script động tương thích VBook) và đối tượng Http
        let scriptBootstrap = """
        var Script = {
            execute: function(scriptContent, functionName) {
                var args = Array.prototype.slice.call(arguments, 2);
                try {
                    eval(scriptContent);
                    var fn = eval(functionName);
                    if (typeof fn === 'function') {
                        return fn.apply(null, args);
                    } else {
                        throw new Error("Function '" + functionName + "' is not defined or not a function.");
                    }
                } catch (e) {
                    console.log("❌ Script.execute error: " + e.message);
                    throw e;
                }
            }
        };

        var Http = {
            _request: function(method, url) {
                var req = {
                    _url: url,
                    _method: method,
                    _headers: {},
                    _params: {},
                    _body: null,

                    header: function(key, value) {
                        this._headers[key] = value;
                        return this;
                    },

                    headers: function(dict) {
                        if (dict) {
                            for (var key in dict) {
                                this._headers[key] = dict[key];
                            }
                        }
                        return this;
                    },

                    param: function(key, value) {
                        this._params[key] = value;
                        return this;
                    },

                    params: function(dict) {
                        if (dict) {
                            for (var key in dict) {
                                this._params[key] = dict[key];
                            }
                        }
                        return this;
                    },

                    body: function(content) {
                        this._body = content;
                        return this;
                    },

                    _execute: function() {
                        var finalUrl = this._url;
                        var paramKeys = Object.keys(this._params);
                        if (paramKeys.length > 0) {
                            var queryString = paramKeys.map(function(key) {
                                var val = req._params[key];
                                return encodeURIComponent(key) + "=" + encodeURIComponent(val !== null && val !== undefined ? val : "");
                            }).join("&");

                            if (this._method.toUpperCase() === "GET") {
                                finalUrl += (finalUrl.indexOf("?") >= 0 ? "&" : "?") + queryString;
                            } else if (!this._body) {
                                this._body = queryString;
                                if (!this._headers["Content-Type"]) {
                                    this._headers["Content-Type"] = "application/x-www-form-urlencoded";
                                }
                            }
                        }

                        var options = {
                            method: this._method,
                            headers: this._headers,
                            body: this._body
                        };

                        return fetch(finalUrl, options);
                    },

                    html: function(encoding) {
                        return this._execute().html(encoding);
                    },

                    string: function(encoding) {
                        return this._execute().text(encoding);
                    },

                    code: function() {
                        return this._execute().status;
                    }
                };
                return req;
            },

            get: function(url) {
                return this._request("GET", url);
            },

            post: function(url) {
                return this._request("POST", url);
            }
        };
        """
        context.evaluateScript(scriptBootstrap)

        let syncFetchBlock: @convention(block) (String, JSValue?) -> [String: Any] = { [weak self] urlString, optionsVal in
            guard let self = self else {
                return ["html": "", "status": 500, "raw": "", "headers": [String: String]()]
            }
            guard !self.isCurrentExecutionCancelled else {
                return ["html": "", "status": 499, "raw": "", "headers": [String: String]()]
            }
            let resolvedUrlString = urlString
            if isEngineDomainBlocked(resolvedUrlString) {
                // AppLogger.shared.log("🚫 [JSExecutor] Blocked network fetch to: \(resolvedUrlString)")
                return ["html": "", "status": 403, "raw": "", "headers": [String: String]()]
            }
            // AppLogger.shared.log("🌐 [JSExecutor] Sync Fetching: \(resolvedUrlString)")
            guard let url = URL(string: resolvedUrlString) else {
                return ["html": "", "status": 400, "raw": "", "headers": [String: String]()]
            }
            var resultHtml = ""
            var resultRawBase64 = ""
            var statusCode = 200
            var responseHeaders: [String: String] = [:]
            let semaphore = DispatchSemaphore(value: 0)

            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

            if let options = optionsVal, options.isObject {
                // Method
                if let methodVal = options.objectForKeyedSubscript("method"), methodVal.isString {
                    request.httpMethod = methodVal.toString().uppercased()
                } else {
                    request.httpMethod = "GET"
                }

                // Headers
                if let headersVal = options.objectForKeyedSubscript("headers"), headersVal.isObject {
                    if let headersDict = headersVal.toDictionary() as? [String: String] {
                        for (key, val) in headersDict {
                            request.setValue(val, forHTTPHeaderField: key)
                        }
                    }
                }

                // Body
                if let bodyVal = options.objectForKeyedSubscript("body") {
                    if bodyVal.isString {
                        request.httpBody = bodyVal.toString().data(using: .utf8)
                    }
                }
            } else {
                request.httpMethod = "GET"
            }

            let taskID = self.reserveNetworkTaskID()
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                defer {
                    self.unregisterNetworkTask(id: taskID)
                    semaphore.signal()
                }
                if error != nil {
                    // AppLogger.shared.log("❌ [JSExecutor] Fetch error: \(error.localizedDescription)")
                    statusCode = 500
                }
                var isBinaryResponse = false
                if let httpResponse = response as? HTTPURLResponse {
                    statusCode = httpResponse.statusCode
                    let mimeType = httpResponse.mimeType?.lowercased() ?? ""
                    isBinaryResponse = mimeType.hasPrefix("audio/") ||
                        mimeType.hasPrefix("video/") ||
                        mimeType.hasPrefix("image/") ||
                        mimeType == "application/octet-stream"
                    for (key, value) in httpResponse.allHeaderFields {
                        if let keyStr = key as? String, let valStr = value as? String {
                            responseHeaders[keyStr] = valStr
                        }
                    }
                }
                if let data = data {
                    // Audio TTS extensions consume base64(). Avoid decoding the
                    // same binary payload as text before encoding it as Base64.
                    if !isBinaryResponse {
                        resultHtml = self.decodeData(data)
                    }
                    resultRawBase64 = data.base64EncodedString()
                }
            }

            guard self.registerNetworkTask(task, id: taskID) else {
                task.cancel()
                return ["html": "", "status": 499, "raw": "", "headers": [String: String]()]
            }
            task.resume()
            let waitResult = semaphore.wait(timeout: .now() + 10.0)
            if waitResult == .timedOut {
                statusCode = 408
                self.unregisterNetworkTask(id: taskID)
                task.cancel()
                // URLSession cancellation normally completes immediately. The
                // bounded wait prevents the callback from mutating result state
                // after this synchronous bridge has returned.
                _ = semaphore.wait(timeout: .now() + 1.0)
            }

            return ["html": resultHtml, "status": statusCode, "raw": resultRawBase64, "headers": responseHeaders]
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
            if (options && options.queries && typeof options.queries === 'object') {
                var qParams = [];
                for (var qKey in options.queries) {
                    if (options.queries.hasOwnProperty(qKey)) {
                        var qVal = options.queries[qKey];
                        qParams.push(encodeURIComponent(qKey) + "=" + encodeURIComponent(qVal !== null && qVal !== undefined ? qVal : ""));
                    }
                }
                if (qParams.length > 0) {
                    var queryString = qParams.join("&");
                    if (url.indexOf("?") === -1) {
                        url = url + "?" + queryString;
                    } else {
                        if (url.endsWith("?") || url.endsWith("&")) {
                            url = url + queryString;
                        } else {
                            url = url + "&" + queryString;
                        }
                    }
                }
            }

            if (options && options.body && typeof options.body === 'object') {
                var params = [];
                for (var key in options.body) {
                    if (options.body.hasOwnProperty(key)) {
                        var val = options.body[key];
                        params.push(encodeURIComponent(key) + "=" + encodeURIComponent(val !== null && val !== undefined ? val : ""));
                    }
                }
                options.body = params.join("&");
                if (!options.headers) {
                    options.headers = {};
                }
                var hasContentType = false;
                for (var h in options.headers) {
                    if (h.toLowerCase() === 'content-type') {
                        hasContentType = true;
                        break;
                    }
                }
                if (!hasContentType) {
                    options.headers["Content-Type"] = "application/x-www-form-urlencoded";
                }
            }

            var res = _nativeSyncFetch(url, options || null);
            var headersMap = res.headers || {};
            return {
                ok: res.status >= 200 && res.status < 300,
                status: res.status,
                headers: {
                    get: function(name) {
                        if (!name) return null;
                        var lowerName = name.toLowerCase();
                        for (var key in headersMap) {
                            if (key.toLowerCase() === lowerName) {
                                return headersMap[key];
                            }
                        }
                        return null;
                    }
                },
                html: function(encoding) {
                    var htmlText = "";
                    if (encoding && res.raw) {
                        htmlText = _nativeDecodeBase64(res.raw, encoding);
                    } else {
                        htmlText = res.html || "";
                    }
                    return Html.parseWithBase(htmlText, url);
                },
                text: function(encoding) {
                    if (encoding && res.raw) {
                        return _nativeDecodeBase64(res.raw, encoding);
                    }
                    return res.html || "";
                },
                json: function() {
                    return JSON.parse(res.html || "{}");
                },
                base64: function() {
                    return res.raw || "";
                }
            };
        };
        """
        context.evaluateScript(fetchBootstrap)

        // Đăng ký các block chạy browser thực tế bằng WKWebView duy trì thực thể
        let browserNewBlock: @convention(block) (String) -> Void = { [weak self] browserId in
            guard let self = self else { return }
            if Thread.isMainThread {
                let loader = WebViewLoader()
                self.activeBrowsers[browserId] = loader
            } else {
                DispatchQueue.main.sync {
                    let loader = WebViewLoader()
                    self.activeBrowsers[browserId] = loader
                }
            }
        }
        context.setObject(browserNewBlock, forKeyedSubscript: "_nativeBrowserNew" as NSCopying & NSObjectProtocol)

        let browserLaunchBlock: @convention(block) (String, String, Double) -> String = { [weak self] browserId, urlString, timeoutMs in
            guard let self = self else { return "" }
            let url = URL(string: urlString)!
            var resultHtml = ""

            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                guard let loader = self.activeBrowsers[browserId] else { semaphore.signal(); return }
                loader.load(url: url, timeout: timeoutMs / 1000.0) { html in
                    resultHtml = html ?? ""
                    semaphore.signal()
                }
            }
            _ = semaphore.wait(timeout: .now() + (timeoutMs / 1000.0) + 1.0)
            return resultHtml
        }
        context.setObject(browserLaunchBlock, forKeyedSubscript: "_nativeBrowserLaunch" as NSCopying & NSObjectProtocol)

        let browserGetHtmlBlock: @convention(block) (String) -> String = { [weak self] browserId in
            guard let self = self else { return "" }
            var resultHtml = ""

            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                guard let loader = self.activeBrowsers[browserId] else { semaphore.signal(); return }
                loader.getHtml { html in
                    resultHtml = html ?? ""
                    semaphore.signal()
                }
            }
            _ = semaphore.wait(timeout: .now() + 5.0)
            return resultHtml
        }
        context.setObject(browserGetHtmlBlock, forKeyedSubscript: "_nativeBrowserGetHtml" as NSCopying & NSObjectProtocol)

        let browserCallJsBlock: @convention(block) (String, String, Double) -> String = { [weak self] browserId, script, waitTimeMs in
            guard let self = self else { return "" }
            var resultStr = ""

            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                guard let loader = self.activeBrowsers[browserId] else { semaphore.signal(); return }
                loader.callJs(script: script, waitTime: waitTimeMs / 1000.0) { res, _ in
                    resultStr = res ?? ""
                    semaphore.signal()
                }
            }
            _ = semaphore.wait(timeout: .now() + (waitTimeMs / 1000.0) + 5.0)
            return resultStr
        }
        context.setObject(browserCallJsBlock, forKeyedSubscript: "_nativeBrowserCallJs" as NSCopying & NSObjectProtocol)

        let browserWaitUrlBlock: @convention(block) (String, String, Double) -> Bool = { [weak self] browserId, targetUrl, timeoutMs in
            guard let self = self else { return false }
            var waitSuccess = false

            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                guard let loader = self.activeBrowsers[browserId] else { semaphore.signal(); return }
                loader.waitUrl(targetUrl: targetUrl, timeout: timeoutMs / 1000.0) { success in
                    waitSuccess = success
                    semaphore.signal()
                }
            }
            _ = semaphore.wait(timeout: .now() + (timeoutMs / 1000.0) + 1.0)
            return waitSuccess
        }
        context.setObject(browserWaitUrlBlock, forKeyedSubscript: "_nativeBrowserWaitUrl" as NSCopying & NSObjectProtocol)

        let browserWaitForReadyBlock: @convention(block) (String, String, Double, Double, Double) -> String = { [weak self] browserId, probeScript, timeoutMs, intervalMs, stablePasses in
            guard let self = self else {
                return makeReadyResponse(ready: false, failed: true, reason: "JSExecutor was deallocated")
            }
            if Thread.isMainThread {
                AppLogger.shared.log("⚠️ [JSExecutor] _nativeBrowserWaitForReady called on Main Thread! Deadlock prevented.")
                return makeReadyResponse(ready: false, failed: true, reason: "Deadlock prevention: Native bridge called on Main Thread")
            }

            var resultJson = ""
            var completed = false
            let lock = NSLock()
            let semaphore = DispatchSemaphore(value: 0)

            func transitionToTerminal(json: String) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if !completed {
                    completed = true
                    resultJson = json
                    semaphore.signal()
                    return true
                }
                return false
            }

            let clampedTimeout = max(1.0, min(60.0, timeoutMs / 1000.0))

            DispatchQueue.main.async {
                lock.lock()
                let alreadyCompleted = completed
                lock.unlock()
                if alreadyCompleted { return }

                guard let loader = self.activeBrowsers[browserId] else {
                    _ = transitionToTerminal(json: makeReadyResponse(ready: false, failed: true, reason: "Browser not found"))
                    return
                }

                loader.waitForReady(
                    probeScript: probeScript,
                    timeoutMs: timeoutMs,
                    intervalMs: intervalMs,
                    stablePasses: Int(stablePasses)
                ) { responseJson in
                    _ = transitionToTerminal(json: responseJson)
                }
            }

            _ = semaphore.wait(timeout: .now() + clampedTimeout + 5.0)

            let fallbackWon = transitionToTerminal(json: makeReadyResponse(ready: false, failed: true, reason: "Semaphore wait timed out", timedOut: true))

            if fallbackWon {
                DispatchQueue.main.async {
                    if let loader = self.activeBrowsers[browserId] {
                        loader.cancelPendingWaitReady(reason: "Semaphore wait timed out", cancelled: false)
                    }
                }
            }

            lock.lock()
            let finalResult = resultJson
            lock.unlock()

            return finalResult
        }
        context.setObject(browserWaitForReadyBlock, forKeyedSubscript: "_nativeBrowserWaitForReady" as NSCopying & NSObjectProtocol)

        let browserCloseBlock: @convention(block) (String) -> Void = { [weak self] browserId in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let loader = self.activeBrowsers[browserId] {
                    loader.cleanUp()
                }
                self.activeBrowsers.removeValue(forKey: browserId)
            }
        }
        context.setObject(browserCloseBlock, forKeyedSubscript: "_nativeBrowserClose" as NSCopying & NSObjectProtocol)

        // Native bridge hooks cho Visible Browser (Trình duyệt có giao diện)
        let browserNewVisibleBlock: @convention(block) (String, String) -> Void = { [weak self] browserId, title in
            guard let self = self else { return }
            let setupLoader = {
                let loader = VisibleWebViewLoader(id: browserId, title: title)
                loader.onClose = { [weak self] in
                    self?.activeVisibleBrowsers.removeValue(forKey: browserId)
                }
                self.activeVisibleBrowsers[browserId] = loader
                Task { @MainActor in
                    loader.presentUIIfNeeded()
                }
            }
            if Thread.isMainThread {
                setupLoader()
            } else {
                DispatchQueue.main.async {
                    setupLoader()
                }
            }
        }
        context.setObject(browserNewVisibleBlock, forKeyedSubscript: "_nativeBrowserNewVisible" as NSCopying & NSObjectProtocol)

        let browserLaunchVisibleBlock: @convention(block) (String, String, Double) -> String = { [weak self] browserId, urlString, timeoutMs in
            guard let self = self else { return "" }
            guard let url = URL(string: urlString) else { return "" }
            var resultHtml = ""

            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                guard let loader = self.activeVisibleBrowsers[browserId] else { semaphore.signal(); return }
                loader.load(url: url, timeout: timeoutMs / 1000.0) { html in
                    resultHtml = html ?? ""
                    semaphore.signal()
                }
            }
            _ = semaphore.wait(timeout: .now() + (timeoutMs / 1000.0) + 1.0)
            return resultHtml
        }
        context.setObject(browserLaunchVisibleBlock, forKeyedSubscript: "_nativeBrowserLaunchVisible" as NSCopying & NSObjectProtocol)

        let browserGetHtmlVisibleBlock: @convention(block) (String) -> String = { [weak self] browserId in
            guard let self = self else { return "" }
            var resultHtml = ""

            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                guard let loader = self.activeVisibleBrowsers[browserId] else { semaphore.signal(); return }
                loader.getHtml { html in
                    resultHtml = html ?? ""
                    semaphore.signal()
                }
            }
            _ = semaphore.wait(timeout: .now() + 5.0)
            return resultHtml
        }
        context.setObject(browserGetHtmlVisibleBlock, forKeyedSubscript: "_nativeBrowserGetHtmlVisible" as NSCopying & NSObjectProtocol)

        let browserCallJsVisibleBlock: @convention(block) (String, String, Double) -> String = { [weak self] browserId, script, waitTimeMs in
            guard let self = self else { return "" }
            var resultStr = ""

            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                guard let loader = self.activeVisibleBrowsers[browserId] else { semaphore.signal(); return }
                loader.callJs(script: script, waitTime: waitTimeMs / 1000.0) { res, _ in
                    resultStr = res ?? ""
                    semaphore.signal()
                }
            }
            _ = semaphore.wait(timeout: .now() + (waitTimeMs / 1000.0) + 5.0)
            return resultStr
        }
        context.setObject(browserCallJsVisibleBlock, forKeyedSubscript: "_nativeBrowserCallJsVisible" as NSCopying & NSObjectProtocol)

        let browserWaitUrlVisibleBlock: @convention(block) (String, String, Double) -> Bool = { [weak self] browserId, targetUrl, timeoutMs in
            guard let self = self else { return false }
            var waitSuccess = false

            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                guard let loader = self.activeVisibleBrowsers[browserId] else { semaphore.signal(); return }
                loader.waitUrl(targetUrl: targetUrl, timeout: timeoutMs / 1000.0) { success in
                    waitSuccess = success
                    semaphore.signal()
                }
            }
            _ = semaphore.wait(timeout: .now() + (timeoutMs / 1000.0) + 1.0)
            return waitSuccess
        }
        context.setObject(browserWaitUrlVisibleBlock, forKeyedSubscript: "_nativeBrowserWaitUrlVisible" as NSCopying & NSObjectProtocol)

        let browserWaitForReadyVisibleBlock: @convention(block) (String, String, Double, Double, Double) -> String = { [weak self] browserId, probeScript, timeoutMs, intervalMs, stablePasses in
            guard let self = self else {
                return makeReadyResponse(ready: false, failed: true, reason: "JSExecutor was deallocated")
            }
            if Thread.isMainThread {
                AppLogger.shared.log("⚠️ [JSExecutor] _nativeBrowserWaitForReadyVisible called on Main Thread! Deadlock prevented.")
                return makeReadyResponse(ready: false, failed: true, reason: "Deadlock prevention: Native bridge called on Main Thread")
            }

            var resultJson = ""
            var completed = false
            let lock = NSLock()
            let semaphore = DispatchSemaphore(value: 0)

            func transitionToTerminal(json: String) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if !completed {
                    completed = true
                    resultJson = json
                    semaphore.signal()
                    return true
                }
                return false
            }

            let clampedTimeout = max(1.0, min(60.0, timeoutMs / 1000.0))

            DispatchQueue.main.async {
                lock.lock()
                let alreadyCompleted = completed
                lock.unlock()
                if alreadyCompleted { return }

                guard let loader = self.activeVisibleBrowsers[browserId] else {
                    _ = transitionToTerminal(json: makeReadyResponse(ready: false, failed: true, reason: "Browser not found"))
                    return
                }

                loader.waitForReady(
                    probeScript: probeScript,
                    timeoutMs: timeoutMs,
                    intervalMs: intervalMs,
                    stablePasses: Int(stablePasses)
                ) { responseJson in
                    _ = transitionToTerminal(json: responseJson)
                }
            }

            _ = semaphore.wait(timeout: .now() + clampedTimeout + 5.0)

            let fallbackWon = transitionToTerminal(json: makeReadyResponse(ready: false, failed: true, reason: "Semaphore wait timed out", timedOut: true))

            if fallbackWon {
                DispatchQueue.main.async {
                    if let loader = self.activeVisibleBrowsers[browserId] {
                        loader.cancelPendingWaitReady(reason: "Semaphore wait timed out", cancelled: false)
                    }
                }
            }

            lock.lock()
            let finalResult = resultJson
            lock.unlock()

            return finalResult
        }
        context.setObject(browserWaitForReadyVisibleBlock, forKeyedSubscript: "_nativeBrowserWaitForReadyVisible" as NSCopying & NSObjectProtocol)

        let browserCloseVisibleBlock: @convention(block) (String) -> Void = { [weak self] browserId in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let loader = self.activeVisibleBrowsers[browserId] {
                    loader.cleanUp()
                }
                self.activeVisibleBrowsers.removeValue(forKey: browserId)
            }
        }
        context.setObject(browserCloseVisibleBlock, forKeyedSubscript: "_nativeBrowserCloseVisible" as NSCopying & NSObjectProtocol)

        // Đăng ký JSCrypto toàn cục
        context.setObject(JSCrypto.self, forKeyedSubscript: "Crypto" as NSCopying & NSObjectProtocol)

        // 9. Đăng ký đối tượng Engine toàn cục (Browser thực tế)
        let engineBootstrap = """
        var Engine = {
            newBrowser: function() {
                var browserId = "browser_" + Math.random().toString(36).substr(2, 9);
                _nativeBrowserNew(browserId);
                return {
                    _id: browserId,
                    launch: function(url, timeout) {
                        console.log("🤖 [Engine.Browser] launch(" + url + ")");
                        var html = _nativeBrowserLaunch(this._id, url, timeout || 5000);
                        return Html.parseWithBase(html, url);
                    },
                    html: function() {
                        var html = _nativeBrowserGetHtml(this._id);
                        return Html.parse(html || "");
                    },
                    close: function() {
                        console.log("🤖 [Engine.Browser] close()");
                        _nativeBrowserClose(this._id);
                    },
                    setUserAgent: function(ua) {
                        console.log("🤖 [Engine.Browser] setUserAgent(" + ua + ")");
                    },
                    callJs: function(script, waitTime) {
                        console.log("🤖 [Engine.Browser] callJs()");
                        var result = _nativeBrowserCallJs(this._id, script, waitTime || 0);
                        return result;
                    },
                    waitUrl: function(url, timeout) {
                        console.log("🤖 [Engine.Browser] waitUrl(" + url + ")");
                        return _nativeBrowserWaitUrl(this._id, url, timeout || 5000);
                    },
                    waitForReady: function(probeScript, timeout, interval, stablePasses) {
                        console.log("🤖 [Engine.Browser] waitForReady()");
                        var jsonStr = _nativeBrowserWaitForReady(
                            this._id,
                            probeScript || "",
                            timeout || 30000,
                            interval || 250,
                            stablePasses || 2
                        );
                        try {
                            return JSON.parse(jsonStr);
                        } catch(e) {
                            return { ready: false, failed: true, reason: "Failed to parse result JSON: " + e.message, timedOut: false, cancelled: false };
                        }
                    }
                };
            },
            newVisibleBrowser: function(title) {
                var browserId = "visible_browser_" + Math.random().toString(36).substr(2, 9);
                _nativeBrowserNewVisible(browserId, title || "");
                return {
                    _id: browserId,
                    launch: function(url, timeout) {
                        console.log("👁️ [Engine.VisibleBrowser] launch(" + url + ")");
                        var html = _nativeBrowserLaunchVisible(this._id, url, timeout || 15000);
                        return Html.parseWithBase(html, url);
                    },
                    html: function() {
                        var html = _nativeBrowserGetHtmlVisible(this._id);
                        return Html.parse(html || "");
                    },
                    close: function() {
                        console.log("👁️ [Engine.VisibleBrowser] close()");
                        _nativeBrowserCloseVisible(this._id);
                    },
                    setUserAgent: function(ua) {
                        console.log("👁️ [Engine.VisibleBrowser] setUserAgent(" + ua + ")");
                    },
                    callJs: function(script, waitTime) {
                        console.log("👁️ [Engine.VisibleBrowser] callJs()");
                        var result = _nativeBrowserCallJsVisible(this._id, script, waitTime || 0);
                        return result;
                    },
                    waitUrl: function(url, timeout) {
                        console.log("👁️ [Engine.VisibleBrowser] waitUrl(" + url + ")");
                        return _nativeBrowserWaitUrlVisible(this._id, url, timeout || 15000);
                    },
                    waitForReady: function(probeScript, timeout, interval, stablePasses) {
                        console.log("👁️ [Engine.VisibleBrowser] waitForReady()");
                        var jsonStr = _nativeBrowserWaitForReadyVisible(
                            this._id,
                            probeScript || "",
                            timeout || 30000,
                            interval || 250,
                            stablePasses || 2
                        );
                        try {
                            return JSON.parse(jsonStr);
                        } catch(e) {
                            return { ready: false, failed: true, reason: "Failed to parse result JSON: " + e.message, timedOut: false, cancelled: false };
                        }
                    }
                };
            }
        };
        """
        context.evaluateScript(engineBootstrap)
    }

    internal func decodeData(_ data: Data) -> String {
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

    public static func cleanAndResolveUrl(_ urlString: String, host: String? = nil) -> String {
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
        }

        // 2. Nếu là URL tương đối (không bắt đầu bằng http:// hoặc https://)
        if !cleaned.lowercased().hasPrefix("http://") && !cleaned.lowercased().hasPrefix("https://") {
            let foundHost = host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !foundHost.isEmpty {
                let separator = cleaned.hasPrefix("/") || foundHost.hasSuffix("/") ? "" : "/"
                cleaned = foundHost + separator + cleaned
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

    internal var isCurrentExecutionCancelled: Bool {
        networkTaskLock.lock()
        defer { networkTaskLock.unlock() }
        return executionCancelled
    }

    internal func reserveNetworkTaskID() -> Int {
        networkTaskLock.lock()
        defer { networkTaskLock.unlock() }
        nextNetworkTaskID &+= 1
        return nextNetworkTaskID
    }

    internal func registerNetworkTask(_ task: URLSessionDataTask, id: Int) -> Bool {
        networkTaskLock.lock()
        defer { networkTaskLock.unlock() }
        guard !executionCancelled else { return false }
        activeNetworkTasks[id] = task
        return true
    }

    internal func unregisterNetworkTask(id: Int) {
        networkTaskLock.lock()
        activeNetworkTasks.removeValue(forKey: id)
        networkTaskLock.unlock()
    }

    internal func beginExecution() {
        networkTaskLock.lock()
        executionCancelled = false
        networkTaskLock.unlock()
    }

    public func cancelCurrentExecution() {
        networkTaskLock.lock()
        executionCancelled = true
        let tasks = Array(activeNetworkTasks.values)
        activeNetworkTasks.removeAll()
        networkTaskLock.unlock()

        for task in tasks {
            task.cancel()
        }
    }

    /// Evaluates an extension script once. Persistent TTS runtimes call this
    /// only when the extension script or configuration identity changes.
    public func prepareScript(_ scriptContent: String) throws {
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
    }
