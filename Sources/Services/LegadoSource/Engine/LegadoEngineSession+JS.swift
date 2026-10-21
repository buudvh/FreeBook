import Foundation

/// Chạy JS trong phiên và các hàm mạng phía sau `java.*` (spec §6).
extension LegadoEngineSession {
    /// Chạy một đoạn JS với `result` (nội dung hiện hành), `baseUrl`, `src`; biến `key`/`page`/`title`/`nextChapterUrl`
    /// lấy từ phiên. Lỗi JS ⇒ `.null` (ghi chẩn đoán); chỉ ném `CancellationError`.
    func evaluateJS(_ code: String, result: LegadoContentNode? = nil, baseUrl: String? = nil) throws -> LegadoContentNode {
        try evaluateScript(code, result: result, baseUrl: baseUrl, src: nil)
    }

    /// `frameContent`: nội dung hiện hành cho `java.getString/getElements` trong đoạn JS (mặc định = `result`). Khác
    /// `result` khi JS đầu trên trang nhận chuỗi thân trang nhưng `java.getString` vẫn dùng cây đã phân tích.
    func evaluateScript(_ code: String, result: LegadoContentNode?, baseUrl: String?, src: String?,
                        frameContent: LegadoContentNode? = nil) throws -> LegadoContentNode {
        let base = baseUrl ?? sourceBase
        ruleFrames.append(RuleFrame(content: frameContent ?? result ?? .null, baseUrl: base, src: src))
        defer { ruleFrames.removeLast() }
        return try runtime.evaluate(code, bindings: jsBindings(result: result, baseUrl: base, src: src))
    }

    func jsBindings(result: LegadoContentNode?, baseUrl: String, src: String?) -> LegadoJSBindings {
        var bindings = LegadoJSBindings()
        bindings.result = result
        bindings.baseUrl = baseUrl
        bindings.src = src
        bindings.key = key
        bindings.page = page
        bindings.title = chapter?.title
        bindings.nextChapterUrl = nextChapterUrl
        return bindings
    }

    // MARK: - java.ajax / connect / get / post / head / webView

    /// `java.ajax(url[, timeout])`: rule URL đầy đủ (option `,{…}` được tôn trọng), thân bất kể mã; lỗi ⇒ `""`.
    func jsAjax(_ url: String, timeoutMs: Double?) throws -> String {
        guard let response = try jsConnect(url, headers: nil, timeoutMs: timeoutMs) else { return "" }
        return response.body
    }

    /// `java.connect(url[, headers])`: như `ajax` nhưng trả phản hồi (có mã); lỗi mạng ⇒ `nil`.
    func jsConnect(_ url: String, headers: String?, timeoutMs: Double? = nil) throws -> LegadoHTTPResponse? {
        do {
            var request = try buildRequest(url, baseUrl: currentFrameBaseUrl)
            if let headers {
                request.headers = LegadoHeaderParser.merge(request.headers, LegadoHeaderParser.pairs(fromText: headers))
            }
            if let timeoutMs, timeoutMs > 0 { request.timeout = timeoutMs / 1000 }
            return try perform(request, allowHTTPError: true)
        } catch {
            if error is CancellationError || cancellation.isCancelled { throw CancellationError() }
            diagnostics.record(.network, "java.ajax/connect \(url.prefix(160)): \(error.localizedDescription)")
            return nil
        }
    }

    /// `java.get/post/head(url, …, headers)`: **không** theo chuyển hướng (§4.7); URL dùng nguyên (không option).
    func jsDirectRequest(method: String, url: String, body: String?, headers: String?) throws -> LegadoHTTPResponse? {
        do {
            let resolved = LegadoURLResolver.absolute(url, base: currentFrameBaseUrl ?? sourceBase)
            var request = LegadoHTTPRequest(url: LegadoURLEncoder.encodeURL(resolved, encoding: .utf8))
            request.method = method
            request.followRedirects = false
            var merged: [(name: String, value: String)] = [(name: "User-Agent", value: LegadoHTTPClient.defaultUserAgent)]
            let sourcePairs = try sourceHeaders(baseUrl: currentFrameBaseUrl)
            merged = LegadoHeaderParser.merge(merged, sourcePairs)
            merged = LegadoHeaderParser.merge(merged, loginHeaders(forURL: resolved, pageURL: currentFrameBaseUrl))
            if let headers {
                merged = LegadoHeaderParser.merge(merged, LegadoHeaderParser.pairs(fromText: headers))
            }
            request.headers = merged
            if method == "POST", let body {
                request.body = Data(body.utf8)
                if request.header("Content-Type") == nil {
                    let isJSON = LegadoEngineJSONParser.parseContainer(body) != nil
                    request.setHeader("Content-Type", isJSON ? "application/json" : "application/x-www-form-urlencoded")
                }
            }
            return try perform(request, allowHTTPError: true)
        } catch {
            if error is CancellationError || cancellation.isCancelled { throw CancellationError() }
            diagnostics.record(.network, "java.\(method.lowercased()) \(url.prefix(160)): \(error.localizedDescription)")
            return nil
        }
    }

    /// `java.webView(html, url, js)`: `html` rỗng ⇒ tải `url`; có `js` ⇒ trả giá trị của nó, không ⇒ HTML trang.
    func jsWebView(html: String?, url: String?, script: String?) throws -> String {
        let target = LegadoURLResolver.absolute(url ?? "", base: currentFrameBaseUrl ?? sourceBase)
        let trimmedHTML = html?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pageURL = target.isEmpty ? sourceBase : target
        do {
            let response = try loadInWebView(url: LegadoURLEncoder.encodeURL(pageURL, encoding: .utf8),
                                             htmlString: trimmedHTML.isEmpty ? nil : html, script: script)
            return response.body
        } catch {
            if error is CancellationError || cancellation.isCancelled { throw CancellationError() }
            diagnostics.record(.network, "java.webView \(pageURL.prefix(160)): \(error.localizedDescription)")
            return ""
        }
    }

    // MARK: - jsLib

    /// Bản tải của một URL `jsLib`: đệm bền trước, không có thì tải (GET thường) rồi lưu.
    func libraryScript(url: String) -> String? {
        if let cached = store.libraryScript(url: url), !cached.isEmpty { return cached }
        do {
            var request = LegadoHTTPRequest(url: LegadoURLEncoder.encodeURL(url, encoding: .utf8))
            request.headers = [(name: "User-Agent", value: LegadoHTTPClient.defaultUserAgent)]
            let response = try perform(request)
            guard !response.body.isEmpty else { return nil }
            store.setLibraryScript(response.body, url: url)
            return response.body
        } catch {
            diagnostics.record(.network, "jsLib \(url): \(error.localizedDescription)")
            return nil
        }
    }
}
