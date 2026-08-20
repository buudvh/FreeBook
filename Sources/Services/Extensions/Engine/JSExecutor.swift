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
                translated = TranslateUtils.translateChapterTitle(text)
            } else if target == "hv" {
                translated = TranslateUtils.translateAuthorHanViet(text)
            } else if isPersonName {
                translated = TranslateUtils.translateAuthorHanViet(text)
            } else {
                translated = TranslateUtils.translateMeta(text)
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

        function __safe_run_extension(functionName, args) {
            try {
                var fn = this[functionName] || eval(functionName);
                if (typeof fn !== 'function') {
                    return Response.error("Hàm '" + functionName + "' không tồn tại trong extension");
                }
                var res = fn.apply(null, args);
                if (res === null || res === undefined) {
                    return Response.error("Extension không trả về dữ liệu (kết quả là " + (res === null ? "null" : "undefined") + ")");
                }
                return res;
            } catch (e) {
                var msg = e && (e.message || e.toString()) ? (e.message || e.toString()) : "Lỗi thực thi Javascript";
                var line = e && e.line ? " (dòng " + e.line + ")" : "";
                return Response.error(msg + line);
            }
        }
        """
        context.evaluateScript(responseBootstrap)

        // 6.4. Đăng ký đối tượng Storage toàn cục (localStorage, cacheStorage, localConfig, localCookie)
        let storageBootstrap = """
        var localStorage = {
            getItem: function(key) {
                var val = _nativeStorageGet(String(key));
                return val !== "" ? val : null;
            },
            setItem: function(key, val) {
                _nativeStorageSet(String(key), String(val !== null && val !== undefined ? val : ""));
            },
            removeItem: function(key) {
                _nativeStorageRemove(String(key));
            },
            clear: function() {
                _nativeStorageClear();
            }
        };

        var __cacheStorageData = {};
        var cacheStorage = {
            getItem: function(key) {
                return __cacheStorageData.hasOwnProperty(key) ? __cacheStorageData[key] : null;
            },
            setItem: function(key, val) {
                __cacheStorageData[key] = String(val !== null && val !== undefined ? val : "");
            },
            removeItem: function(key) {
                delete __cacheStorageData[key];
            },
            clear: function() {
                __cacheStorageData = {};
            }
        };

        var localConfig = {
            getItem: function(key) {
                if (typeof _injectedConfigs !== 'undefined' && _injectedConfigs && _injectedConfigs.hasOwnProperty(key)) {
                    return _injectedConfigs[key];
                }
                if (typeof this[key] !== 'undefined') {
                    return this[key];
                }
                return null;
            },
            get: function(key) {
                return this.getItem(key);
            }
        };

        var __cookieData = "";
        var localCookie = {
            setCookie: function(cookieStr) {
                __cookieData = String(cookieStr || "");
            },
            getCookie: function(url) {
                return __cookieData;
            }
        };
        """
        context.evaluateScript(storageBootstrap)

        // 6.5. Đăng ký đối tượng UserAgent toàn cục với đầy đủ phương thức VBook
        let userAgentBootstrap = """
        var UserAgent = {
            system: function() { return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"; },
            android: function() { return "Mozilla/5.0 (Linux; Android 13; SM-S901B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"; },
            ios: function() { return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"; },
            pc: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; },
            computer: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; },
            chrome: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; },
            mobile: function() { return "Mozilla/5.0 (Linux; Android 13; SM-S901B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"; },
            safari: function() { return "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"; },
            firefox: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:120.0) Gecko/20100101 Firefox/120.0"; },
            mac: function() { return "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; },
            macos: function() { return "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; },
            windows: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; },
            random: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; },
            default: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; },
            get: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; }
        };
        """
        context.evaluateScript(userAgentBootstrap)

        // 6.6. Đăng ký đối tượng toàn cục Qt (Quick Translator & Utilities)
        let qtBootstrap = """
        var Qt = {
            translate: function(text, to, extras) {
                return _nativeQtTranslate(text || "", to || "vi", extras || null);
            },
            atob: function(s) { return atob(s); },
            btoa: function(s) { return btoa(s); },
            md5: function(s) { return typeof Crypto !== 'undefined' && Crypto.md5 ? Crypto.md5(s) : s; },
            sha256: function(s) { return typeof Crypto !== 'undefined' && Crypto.sha256 ? Crypto.sha256(s) : s; },
            sha1: function(s) { return typeof Crypto !== 'undefined' && Crypto.sha1 ? Crypto.sha1(s) : s; },
            sha512: function(s) { return typeof Crypto !== 'undefined' && Crypto.sha512 ? Crypto.sha512(s) : s; },
            formatDate: function(date, format) { return date ? (typeof date === 'object' && date.toISOString ? date.toISOString().split('T')[0] : date.toString()) : ""; },
            formatDateTime: function(date, format) { return date ? (typeof date === 'object' && date.toISOString ? date.toISOString() : date.toString()) : ""; },
            formatTime: function(date, format) { return date ? (typeof date === 'object' && date.toTimeString ? date.toTimeString() : date.toString()) : ""; },
            include: function(file) { if (typeof load === 'function') load(file); },
            resolvedUrl: function(url) { return url; },
            openUrlExternally: function(url) { return true; },
            platform: { os: "ios" },
            point: function(x, y) { return { x: x || 0, y: y || 0 }; },
            size: function(w, h) { return { width: w || 0, height: h || 0 }; },
            rect: function(x, y, w, h) { return { x: x || 0, y: y || 0, width: w || 0, height: h || 0 }; },
            rgba: function(r, g, b, a) { return "rgba(" + Math.round(r*255) + "," + Math.round(g*255) + "," + Math.round(b*255) + "," + (a !== undefined ? a : 1) + ")"; },
            hsla: function(h, s, l, a) { return "hsla(" + Math.round(h*360) + "," + Math.round(s*100) + "%," + Math.round(l*100) + "%," + (a !== undefined ? a : 1) + ")"; },
            quit: function() {},
            exit: function() {}
        };
        """
        context.evaluateScript(qtBootstrap)

        // 6.7. Đăng ký đối tượng Script toàn cục (hỗ trợ thực thi script động tương thích VBook) và đối tượng Http
        let scriptBootstrap = """
        var Script = {
            execute: function(scriptOrName, functionName) {
                var args = Array.prototype.slice.call(arguments, 2);
                try {
                    var isFile = false;
                    if (typeof scriptOrName === 'string') {
                        var trimmed = scriptOrName.trim();
                        if (trimmed.endsWith(".js") || (!trimmed.includes(";") && !trimmed.includes("\\n") && !trimmed.includes("{") && !trimmed.includes(" "))) {
                            if (typeof load === 'function') {
                                load(trimmed.endsWith(".js") ? trimmed : (trimmed + ".js"));
                                isFile = true;
                            }
                        }
                    }
                    if (!isFile) {
                        eval(scriptOrName);
                    }
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
                    _method: method || "GET",
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

                    contentType: function(type) {
                        this._headers["Content-Type"] = type;
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

                    text: function(encoding) {
                        return this._execute().text(encoding);
                    },

                    json: function() {
                        return this._execute().json();
                    },

                    table: function() {
                        return this._execute().json();
                    },

                    code: function() {
                        return this._execute().status;
                    },

                    status: function() {
                        return this._execute().status;
                    },

                    base64: function() {
                        return this._execute().base64();
                    },

                    headers: function() {
                        return this._execute().headers;
                    }
                };
                return req;
            },

            get: function(url) {
                return this._request("GET", url);
            },

            post: function(url) {
                return this._request("POST", url);
            },

            request: function(methodOrUrl, url) {
                if (url !== undefined) {
                    return this._request(methodOrUrl, url);
                } else {
                    return this._request("GET", methodOrUrl);
                }
            },

            head: function(url) {
                return this._request("HEAD", url);
            },

            put: function(url) {
                return this._request("PUT", url);
            },

            delete: function(url) {
                return this._request("DELETE", url);
            },

            patch: function(url) {
                return this._request("PATCH", url);
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
            var statusText = "OK"
            var finalUrl = resolvedUrlString
            var responseHeaders: [String: String] = [:]
            var timeoutSeconds: TimeInterval = 15.0
            let semaphore = DispatchSemaphore(value: 0)

            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

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
                }
            }

            guard self.registerNetworkTask(task, id: taskID) else {
                task.cancel()
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
        let fetchBootstrap = """
        var fetch = function(url, options) {
            var originalUrl = url;
            var originalHeaders = (options && options.headers) ? options.headers : {};

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
            var responseObj = {
                ok: res.status >= 200 && res.status < 300,
                status: res.status,
                statusText: res.statusText || (res.status === 200 ? "OK" : "Status " + res.status),
                url: res.url || originalUrl,
                headers: headersMap,
                header: function(name) {
                    if (!name) return null;
                    var lower = name.toLowerCase();
                    for (var k in headersMap) {
                        if (k.toLowerCase() === lower) return headersMap[k];
                    }
                    return null;
                },
                html: function(encoding) {
                    var htmlText = "";
                    if (encoding && res.raw) {
                        htmlText = _nativeDecodeBase64(res.raw, encoding);
                    } else {
                        htmlText = res.html || "";
                    }
                    return Html.parseWithBase(htmlText, res.url || originalUrl);
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
                },
                blob: function() {
                    var contentType = this.header("content-type") || "application/octet-stream";
                    var rawBase64 = res.raw || "";
                    return {
                        size: Math.round(rawBase64.length * 3 / 4),
                        type: contentType,
                        base64: function() { return rawBase64; }
                    };
                },
                request: {
                    url: originalUrl,
                    headers: originalHeaders
                }
            };

            responseObj.headers.get = function(name) {
                return responseObj.header(name);
            };

            return responseObj;
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
                    launchAsync: function(url) {
                        console.log("🤖 [Engine.Browser] launchAsync(" + url + ")");
                        _nativeBrowserLaunchAsync(this._id, url);
                    },
                    html: function(timeout) {
                        if (timeout && timeout > 0) {
                            sleep(timeout);
                        }
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
                    waitUrl: function(urls, timeout) {
                        console.log("🤖 [Engine.Browser] waitUrl()");
                        return _nativeBrowserWaitUrl(this._id, urls, timeout || 5000);
                    },
                    block: function(patterns) {
                        console.log("🤖 [Engine.Browser] block()");
                        var arr = Array.isArray(patterns) ? patterns : [patterns];
                        _nativeBrowserBlock(this._id, arr);
                    },
                    urls: function() {
                        return _nativeBrowserGetUrls(this._id);
                    },
                    getVariable: function(varName) {
                        return this.callJs(varName, 0);
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
                    launchAsync: function(url) {
                        console.log("👁️ [Engine.VisibleBrowser] launchAsync(" + url + ")");
                        _nativeBrowserLaunchAsyncVisible(this._id, url);
                    },
                    html: function(timeout) {
                        if (timeout && timeout > 0) {
                            sleep(timeout);
                        }
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
                    waitUrl: function(urls, timeout) {
                        console.log("👁️ [Engine.VisibleBrowser] waitUrl()");
                        return _nativeBrowserWaitUrlVisible(this._id, urls, timeout || 15000);
                    },
                    block: function(patterns) {
                        console.log("👁️ [Engine.VisibleBrowser] block()");
                        var arr = Array.isArray(patterns) ? patterns : [patterns];
                        _nativeBrowserBlockVisible(this._id, arr);
                    },
                    urls: function() {
                        return _nativeBrowserGetUrlsVisible(this._id);
                    },
                    getVariable: function(varName) {
                        return this.callJs(varName, 0);
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
        return TextEncodingDecoder.decode(data)
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
            throw NSError(domain: "JSExecutor", code: -501, userInfo: [NSLocalizedDescriptionKey: "JS Compile error: \(desc)"])
        }
    }
}

