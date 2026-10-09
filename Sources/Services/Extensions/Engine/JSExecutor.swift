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
    internal var injectedConfigs: [String: Any] = [:]
    /// Trace của lượt debug. Luồng đọc/tải production truyền `nil` và vì thế hành vi không đổi; xem
    /// `JSExecutor+Debug`. Cố ý **không** phải shared/singleton: mỗi run có sink riêng, đúng như mỗi
    /// run có một `JSExecutor` riêng.
    internal let debugSink: ExtensionDebugEventSink?

    public init(
        localPath: String? = nil,
        downloadUrl: String? = nil,
        debugSink: ExtensionDebugEventSink? = nil
    ) {
        self.context = JSContext()
        self.localPath = localPath
        self.downloadUrl = downloadUrl
        self.debugSink = debugSink

        // 1. Cấu hình Exception Handler
        context.exceptionHandler = { [weak self] context, exception in
            let desc = exception?.toString() ?? "Unknown Javascript error"
            let line = exception?.objectForKeyedSubscript("line")?.toString() ?? "unknown"
            let column = exception?.objectForKeyedSubscript("column")?.toString() ?? "unknown"
            let stack = exception?.objectForKeyedSubscript("stack")?.toString() ?? "no stacktrace"
            AppLogger.shared.log("❌ JSContext Exception: \(desc) at line \(line), column \(column)")
            AppLogger.shared.log("🥞 JS Stacktrace: \(stack)")
            self?.emitDebugException(description: desc, line: line, column: column, stack: stack)
        }

        // 2. Đăng ký JSHtml namespace cho JS với tên "Html"
        context.setObject(JSHtml.self, forKeyedSubscript: "Html" as NSCopying & NSObjectProtocol)

        // 3. Đăng ký hàm fetch toàn cục (đã được ghi đè bằng sync fetch ở dưới)

        // 4. Định nghĩa console.log để debug từ tiện ích dễ hơn
        let logBlock: @convention(block) () -> Void = { [weak self] in
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
            self?.emitDebugConsole(message)
        }

        let console = JSValue(newObjectIn: context)
        console?.setObject(logBlock, forKeyedSubscript: "log" as NSCopying & NSObjectProtocol)
        context.setObject(console, forKeyedSubscript: "console" as NSCopying & NSObjectProtocol)
        context.setObject(console, forKeyedSubscript: "Console" as NSCopying & NSObjectProtocol)
        context.setObject(logBlock, forKeyedSubscript: "print" as NSCopying & NSObjectProtocol)

        let logObj = JSValue(newObjectIn: context)
        logObj?.setObject(logBlock, forKeyedSubscript: "log" as NSCopying & NSObjectProtocol)
        context.setObject(logObj, forKeyedSubscript: "Log" as NSCopying & NSObjectProtocol)

        // Đăng ký sleep đồng bộ chuẩn Rhino / VBook
        let sleepBlock: @convention(block) (Int) -> Void = { ms in
            guard ms > 0 else { return }
            Thread.sleep(forTimeInterval: Double(ms) / 1000.0)
        }
        context.setObject(sleepBlock, forKeyedSubscript: "sleep" as NSCopying & NSObjectProtocol)

        // Đăng ký toast / Toast chuẩn VBook
        let toastBlock: @convention(block) (String) -> Void = { msg in
            AppLogger.shared.log("🍞 JS Toast: \(msg)")
        }
        context.setObject(toastBlock, forKeyedSubscript: "toast" as NSCopying & NSObjectProtocol)

        let toastObj = JSValue(newObjectIn: context)
        toastObj?.setObject(toastBlock, forKeyedSubscript: "show" as NSCopying & NSObjectProtocol)
        toastObj?.setObject(toastBlock, forKeyedSubscript: "makeText" as NSCopying & NSObjectProtocol)
        context.setObject(toastObj, forKeyedSubscript: "Toast" as NSCopying & NSObjectProtocol)

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

        // Đăng ký native bridges cho Storage (localStorage)
        let extStoragePrefix = "vbook_ext_storage_" + (self.localPath?.md5() ?? "global") + "_"
        let storageGetBlock: @convention(block) (String) -> String = { key in
            UserDefaults.standard.string(forKey: extStoragePrefix + key) ?? ""
        }
        context.setObject(storageGetBlock, forKeyedSubscript: "_nativeStorageGet" as NSCopying & NSObjectProtocol)

        let storageSetBlock: @convention(block) (String, String) -> Void = { key, val in
            UserDefaults.standard.set(val, forKey: extStoragePrefix + key)
        }
        context.setObject(storageSetBlock, forKeyedSubscript: "_nativeStorageSet" as NSCopying & NSObjectProtocol)

        let storageRemoveBlock: @convention(block) (String) -> Void = { key in
            UserDefaults.standard.removeObject(forKey: extStoragePrefix + key)
        }
        context.setObject(storageRemoveBlock, forKeyedSubscript: "_nativeStorageRemove" as NSCopying & NSObjectProtocol)

        let storageClearBlock: @convention(block) () -> Void = {
            let defaults = UserDefaults.standard
            for (k, _) in defaults.dictionaryRepresentation() {
                if k.hasPrefix(extStoragePrefix) {
                    defaults.removeObject(forKey: k)
                }
            }
        }
        context.setObject(storageClearBlock, forKeyedSubscript: "_nativeStorageClear" as NSCopying & NSObjectProtocol)

        // Đăng ký native bridge cho Quick Translator (Qt.translate)
        let qtTranslateBlock: @convention(block) (String, String, JSValue?) -> [String: Any] = { text, toLang, extrasVal in
            guard !text.isEmpty else {
                return ["translateText": "", "segments": []]
            }
            let target = toLang.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            var isChapterName = false
            var isFirstLineChapterName = false
            var isFirstCapitalize = false
            var isPersonName = false

            if let extras = extrasVal, extras.isObject {
                if let chapVal = extras.objectForKeyedSubscript("chapter_name"), chapVal.isBoolean {
                    isChapterName = chapVal.toBool()
                }
                if let firstChapVal = extras.objectForKeyedSubscript("first_line_chapter_name"), firstChapVal.isBoolean {
                    isFirstLineChapterName = firstChapVal.toBool()
                }
                if let firstCapVal = extras.objectForKeyedSubscript("first_capitalize"), firstCapVal.isBoolean {
                    isFirstCapitalize = firstCapVal.toBool()
                }
                if let personVal = extras.objectForKeyedSubscript("person_name"), personVal.isBoolean {
                    isPersonName = personVal.toBool()
                }
            }

            var translated = ""
            if isChapterName || isFirstLineChapterName {
                // Qt bridge **không** áp rule dịch: bản dịch ở đây đi ra ngoài cho extension dùng,
                // phải giữ đúng hành vi tra từ điển thuần như trước.
                translated = TranslateUtils.translateChapterTitle(text, applyingQuickTranslationRules: false)
            } else if target == "hv" {
                translated = TranslateUtils.translateAuthorHanViet(text)
            } else if isPersonName {
                translated = TranslateUtils.translateAuthorHanViet(text)
            } else {
                translated = TranslateUtils.translateMeta(text, applyingQuickTranslationRules: false)
            }

            if isFirstCapitalize && !translated.isEmpty {
                let firstChar = translated.prefix(1).uppercased()
                let remaining = translated.dropFirst()
                translated = firstChar + remaining
            }

            let spans = TranslateUtils.buildTranslationSpans(original: text, translated: translated)
            let segments: [[String: Any]] = spans.map { s in
                [
                    "srcStart": s.originalLocation,
                    "srcLen": s.originalLength,
                    "transStart": s.translatedLocation,
                    "transLen": s.translatedLength,
                    "type": 2
                ]
            }

            return ["translateText": translated, "segments": segments]
        }
        context.setObject(qtTranslateBlock, forKeyedSubscript: "_nativeQtTranslate" as NSCopying & NSObjectProtocol)

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

        // 6. Đăng ký đối tượng Response toàn cục và runner an toàn __safe_run_extension
        let responseBootstrap = JSCoreBootstrapScripts.response
        context.evaluateScript(responseBootstrap)

        // 6.4. Đăng ký đối tượng Storage toàn cục (localStorage, cacheStorage, localConfig, localCookie)
        let storageBootstrap = JSExtensionStorageBridge.bootstrap
        context.evaluateScript(storageBootstrap)

        // 6.5. Đăng ký đối tượng UserAgent toàn cục với đầy đủ phương thức VBook
        let userAgentBootstrap = JSCoreBootstrapScripts.userAgent
        context.evaluateScript(userAgentBootstrap)

        // 6.6. Đăng ký đối tượng toàn cục Qt (Quick Translator & Utilities)
        let qtBootstrap = JSQtTranslateBridge.bootstrap
        context.evaluateScript(qtBootstrap)

        // 6.7. Đăng ký đối tượng Script toàn cục (hỗ trợ thực thi script động tương thích VBook) và đối tượng Http
        let scriptBootstrap = JSScriptHttpBootstrapScript.source
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
                self.emitDebugFetchFinished(taskID: 0, url: resolvedUrlString, status: 403, statusText: "Blocked domain", bytes: 0, startedAt: Date())
                return ["html": "", "status": 403, "raw": "", "headers": [String: String]()]
            }
            // AppLogger.shared.log("🌐 [JSExecutor] Sync Fetching: \(resolvedUrlString)")
            guard let url = URL(string: resolvedUrlString) else {
                self.emitDebugFetchFinished(taskID: 0, url: resolvedUrlString, status: 400, statusText: "URL không hợp lệ", bytes: 0, startedAt: Date())
                return ["html": "", "status": 400, "raw": "", "headers": [String: String]()]
            }
            var resultHtml = ""
            var resultRawBase64 = ""
            var statusCode = 200
            var statusText = "OK"
            var finalUrl = resolvedUrlString
            var responseHeaders: [String: String] = [:]
            var timeoutSeconds: TimeInterval = 15.0
            let semaphore = DispatchSemaphore(value: 0)

            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

            if let handleCookies = self.injectedConfigs["http_should_handle_cookies"] as? Bool {
                request.httpShouldHandleCookies = handleCookies
            } else if let handleCookiesStr = self.injectedConfigs["http_should_handle_cookies"] as? String {
                request.httpShouldHandleCookies = (handleCookiesStr.lowercased() == "true")
            }

            if let options = optionsVal, options.isObject {
                // Timeout
                if let timeoutVal = options.objectForKeyedSubscript("timeout"), timeoutVal.isNumber {
                    let ms = timeoutVal.toDouble()
                    if ms > 0 {
                        timeoutSeconds = max(1.0, min(120.0, ms / 1000.0))
                    }
                }

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
            request.timeoutInterval = timeoutSeconds

            let taskID = self.reserveNetworkTaskID()
            let fetchStartedAt = Date()
            self.emitDebugFetchStarted(taskID: taskID, url: resolvedUrlString, method: request.httpMethod ?? "GET")
            var responseByteCount = 0
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                defer {
                    self.unregisterNetworkTask(id: taskID)
                    semaphore.signal()
                }
                if error != nil {
                    // AppLogger.shared.log("❌ [JSExecutor] Fetch error: \(error.localizedDescription)")
                    statusCode = 500
                    statusText = error?.localizedDescription ?? "Network Error"
                }
                var isBinaryResponse = false
                if let httpResponse = response as? HTTPURLResponse {
                    statusCode = httpResponse.statusCode
                    statusText = HTTPURLResponse.localizedString(forStatusCode: statusCode)
                    if let u = httpResponse.url?.absoluteString, !u.isEmpty {
                        finalUrl = u
                    }
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
                    responseByteCount = data.count
                }
            }

            guard self.registerNetworkTask(task, id: taskID) else {
                task.cancel()
                self.emitDebugFetchFinished(
                    taskID: taskID,
                    url: resolvedUrlString,
                    status: 499,
                    statusText: "Cancelled",
                    bytes: 0,
                    startedAt: fetchStartedAt
                )
                return ["html": "", "status": 499, "statusText": "Cancelled", "raw": "", "headers": [String: String](), "url": resolvedUrlString]
            }
            task.resume()
            let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
            if waitResult == .timedOut {
                statusCode = 408
                statusText = "Request Timeout"
                self.unregisterNetworkTask(id: taskID)
                task.cancel()
                // URLSession cancellation normally completes immediately. The
                // bounded wait prevents the callback from mutating result state
                // after this synchronous bridge has returned.
                _ = semaphore.wait(timeout: .now() + 1.0)
            }

            self.emitDebugFetchFinished(
                taskID: taskID,
                url: finalUrl,
                status: statusCode,
                statusText: statusText,
                bytes: responseByteCount,
                startedAt: fetchStartedAt
            )
            return ["html": resultHtml, "status": statusCode, "statusText": statusText, "raw": resultRawBase64, "headers": responseHeaders, "url": finalUrl]
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
        let fetchBootstrap = JSFetchBootstrapScript.source
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

        let browserLaunchAsyncBlock: @convention(block) (String, String) -> Void = { [weak self] browserId, urlString in
            guard let self = self, let url = URL(string: urlString) else { return }
            DispatchQueue.main.async {
                guard let loader = self.activeBrowsers[browserId] else { return }
                loader.loadAsync(url: url)
            }
        }
        context.setObject(browserLaunchAsyncBlock, forKeyedSubscript: "_nativeBrowserLaunchAsync" as NSCopying & NSObjectProtocol)

        let browserBlockPatternsBlock: @convention(block) (String, [String]) -> Void = { [weak self] browserId, patterns in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard let loader = self.activeBrowsers[browserId] else { return }
                loader.block(patterns: patterns)
            }
        }
        context.setObject(browserBlockPatternsBlock, forKeyedSubscript: "_nativeBrowserBlock" as NSCopying & NSObjectProtocol)

        let browserGetUrlsBlock: @convention(block) (String) -> [String] = { [weak self] browserId in
            guard let self = self else { return [] }
            var urls: [String] = []
            if Thread.isMainThread {
                urls = self.activeBrowsers[browserId]?.interceptedUrls ?? []
            } else {
                DispatchQueue.main.sync {
                    urls = self.activeBrowsers[browserId]?.interceptedUrls ?? []
                }
            }
            return urls
        }
        context.setObject(browserGetUrlsBlock, forKeyedSubscript: "_nativeBrowserGetUrls" as NSCopying & NSObjectProtocol)

        let browserWaitUrlBlock: @convention(block) (String, JSValue, Double) -> Bool = { [weak self] browserId, targetUrlsVal, timeoutMs in
            guard let self = self else { return false }
            var waitSuccess = false
            var targets: [String] = []
            if targetUrlsVal.isArray {
                if let arr = targetUrlsVal.toArray() as? [String] {
                    targets = arr
                }
            } else if targetUrlsVal.isString {
                targets = [targetUrlsVal.toString()]
            }

            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                guard let loader = self.activeBrowsers[browserId] else { semaphore.signal(); return }
                loader.waitUrl(targetUrls: targets, timeout: timeoutMs / 1000.0) { success in
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

        let browserLaunchAsyncVisibleBlock: @convention(block) (String, String) -> Void = { [weak self] browserId, urlString in
            guard let self = self, let url = URL(string: urlString) else { return }
            DispatchQueue.main.async {
                guard let loader = self.activeVisibleBrowsers[browserId] else { return }
                loader.loadAsync(url: url)
            }
        }
        context.setObject(browserLaunchAsyncVisibleBlock, forKeyedSubscript: "_nativeBrowserLaunchAsyncVisible" as NSCopying & NSObjectProtocol)

        let browserBlockVisibleBlock: @convention(block) (String, [String]) -> Void = { [weak self] browserId, patterns in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard let loader = self.activeVisibleBrowsers[browserId] else { return }
                loader.block(patterns: patterns)
            }
        }
        context.setObject(browserBlockVisibleBlock, forKeyedSubscript: "_nativeBrowserBlockVisible" as NSCopying & NSObjectProtocol)

        let browserGetUrlsVisibleBlock: @convention(block) (String) -> [String] = { [weak self] browserId in
            guard let self = self else { return [] }
            var urls: [String] = []
            if Thread.isMainThread {
                urls = self.activeVisibleBrowsers[browserId]?.interceptedUrls ?? []
            } else {
                DispatchQueue.main.sync {
                    urls = self.activeVisibleBrowsers[browserId]?.interceptedUrls ?? []
                }
            }
            return urls
        }
        context.setObject(browserGetUrlsVisibleBlock, forKeyedSubscript: "_nativeBrowserGetUrlsVisible" as NSCopying & NSObjectProtocol)

        let browserWaitUrlVisibleBlock: @convention(block) (String, JSValue, Double) -> Bool = { [weak self] browserId, targetUrlsVal, timeoutMs in
            guard let self = self else { return false }
            var waitSuccess = false
            var targets: [String] = []
            if targetUrlsVal.isArray {
                if let arr = targetUrlsVal.toArray() as? [String] {
                    targets = arr
                }
            } else if targetUrlsVal.isString {
                targets = [targetUrlsVal.toString()]
            }

            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                guard let loader = self.activeVisibleBrowsers[browserId] else { semaphore.signal(); return }
                loader.waitUrl(targetUrls: targets, timeout: timeoutMs / 1000.0) { success in
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
        let engineBootstrap = JSEngineBootstrapScript.source
        context.evaluateScript(engineBootstrap)
    }

    internal func decodeData(_ data: Data) -> String {
        return TextEncodingDecoder.decode(data)
    }

    public static func cleanAndResolveUrl(_ urlString: String, host: String? = nil) -> String {
        ExtensionURLFormatter.cleanAndResolve(urlString, host: host)
    }

    /// Inject các cấu hình dưới dạng biến toàn cục vào JSContext
    public func injectGlobals(_ globals: [String: Any]) {
        self.injectedConfigs = globals
        for (key, value) in globals {
            context.setObject(value, forKeyedSubscript: key as NSCopying & NSObjectProtocol)
        }
        context.setObject(globals, forKeyedSubscript: "_injectedConfigs" as NSCopying & NSObjectProtocol)
    }

    /// Kiểm tra tính hợp lệ cú pháp của script JS trong môi trường runtime đầy đủ của extension
    public func validateSyntax(_ scriptContent: String) -> (isValid: Bool, errorMessage: String?) {
        var syntaxError: String? = nil
        context.exceptionHandler = { _, exception in
            if let exc = exception {
                syntaxError = exc.toString()
            }
        }

        _ = context.evaluateScript(scriptContent)
        if let err = syntaxError {
            return (false, err)
        }
        return (true, nil)
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

        emitDebugCancelled()

        for task in tasks {
            task.cancel()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for loader in self.activeBrowsers.values {
                loader.cancelPendingWaitReady(reason: "cancelled", cancelled: true)
                loader.webView.stopLoading()
            }
            self.activeBrowsers.removeAll()
            for loader in self.activeVisibleBrowsers.values {
                loader.cleanUp()
            }
            self.activeVisibleBrowsers.removeAll()
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
            emitDebugCompileFailed(desc)
            throw NSError(domain: "JSExecutor", code: -501, userInfo: [NSLocalizedDescriptionKey: "JS Compile error: \(desc)"])
        }
    }
}

