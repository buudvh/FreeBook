import Foundation

/// Dựng và gửi request của luồng chính (spec §3, §4).
extension LegadoEngineSession {
    /// Dựng request từ rule URL (§3.2) rồi gửi. Luồng chính: HTTP ≥ 400 ném `.httpStatus` (thân giữ trong lỗi) trừ khi
    /// `allowHTTPError`. `baseUrl` nil ⇒ URL gốc của nguồn (đúng cho `searchUrl`/mục khám phá); trường URL lấy từ trang
    /// thì truyền URL cuối của trang. `content` = nội dung cho placeholder rule (`{{$.id}}`) nếu có.
    /// `webJs` = `ruleContent.webJs`, chỉ dùng khi request tải bằng WebView (§4.4).
    /// `sourceRegex` (spec §9.4) chỉ có tác dụng khi request đi WebView: URL tài nguyên đầu tiên khớp thành thân.
    ///
    /// Đây là cửa **luồng chính**: `loginCheckJs` của nguồn (nếu có) chạy sau mỗi request ở đây, trước khi phân tích
    /// thân (spec §10.7); `java.ajax`/`connect`… đi thẳng `perform` nên không kích hoạt nó.
    func fetch(_ urlRule: String, baseUrl: String? = nil, key: String? = nil, page: Int? = nil,
               content: LegadoContentNode? = nil, webJs: String? = nil, sourceRegex: String? = nil,
               allowHTTPError: Bool = false) throws -> LegadoHTTPResponse {
        var request = try buildRequest(urlRule, baseUrl: baseUrl, key: key, page: page, content: content)
        if request.useWebView, let sourceRegex, !sourceRegex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.sourceRegex = sourceRegex
        }
        guard !request.isDataURL, !isRunningLoginCheck, let check = loginCheckScript else {
            return try perform(request, webJs: webJs, allowHTTPError: allowHTTPError)
        }
        let response = try perform(request, webJs: webJs, allowHTTPError: true)
        let checked = try runLoginCheck(check, response: response, request: request, ruleUrl: urlRule,
                                        baseUrl: baseUrl, key: key, page: page, webJs: webJs)
        if checked.statusCode >= 400 && !allowHTTPError {
            diagnostics.record(.http, "HTTP \(checked.statusCode) \(request.url)")
            throw LegadoEngineError.httpStatus(code: checked.statusCode, url: checked.finalURL,
                                               body: String(checked.body.prefix(4000)))
        }
        return checked
    }

    /// Chỉ dựng request (§3.2 bước 1–7), không gửi. `key`/`page` (nếu truyền) đè biến JS trong lúc dựng.
    func buildRequest(_ urlRule: String, baseUrl: String? = nil, key: String? = nil, page: Int? = nil,
                      content: LegadoContentNode? = nil) throws -> LegadoHTTPRequest {
        let savedKey = self.key
        let savedPage = self.page
        if let key { self.key = key }
        self.page = page ?? self.page ?? 1
        defer {
            self.key = savedKey
            self.page = savedPage
        }
        let base = (baseUrl?.isEmpty ?? true) ? sourceBase : (baseUrl ?? sourceBase)
        return try LegadoURLBuilder(session: self).build(urlRule, baseUrl: base, page: self.page ?? 1, content: content)
    }

    /// Gửi một request đã dựng: rate limiter, cookie, chuyển hướng, thử lại, giải mã thân.
    func perform(_ request: LegadoHTTPRequest, webJs: String? = nil, allowHTTPError: Bool = false) throws -> LegadoHTTPResponse {
        try checkCancellation()
        if request.isDataURL {
            return try recordingRequest(request) {
                guard let response = LegadoDataURL.response(for: request) else {
                    throw LegadoEngineError.invalidURL(String(request.url.prefix(120)))
                }
                return response
            }
        }
        guard LegadoURLResolver.hasHTTPScheme(request.url), URL(string: request.url) != nil else {
            throw LegadoEngineError.invalidURL(request.url)
        }
        try rateLimiter?.acquire(cancellation: cancellation)
        let response = try recordingRequest(request) {
            try (request.useWebView ? performWebView(request, webJs: webJs) : performHTTP(request))
        }
        if response.statusCode >= 400 && !allowHTTPError {
            diagnostics.record(.http, "HTTP \(response.statusCode) \(request.url)")
            throw LegadoEngineError.httpStatus(code: response.statusCode, url: response.finalURL,
                                               body: String(response.body.prefix(4000)))
        }
        return response
    }

    // MARK: - HTTP

    private func performHTTP(_ request: LegadoHTTPRequest) throws -> LegadoHTTPResponse {
        var attempt = 0
        while true {
            do {
                return try performHTTPOnce(request)
            } catch {
                if error is CancellationError || cancellation.isCancelled { throw CancellationError() }
                if error is LegadoEngineError { throw error }
                if attempt < request.retryCount, LegadoHTTPClient.isTransient(error) {
                    attempt += 1
                    try cancellation.sleep(0.5)
                    continue
                }
                throw Self.engineError(error, url: request.url)
            }
        }
    }

    private func performHTTPOnce(_ request: LegadoHTTPRequest) throws -> LegadoHTTPResponse {
        var currentURL = request.url
        var method = request.method
        var includeBody = true
        var receivedCookies: [String: String] = [:]
        for _ in 0..<10 {
            guard let url = URL(string: currentURL) else { throw LegadoEngineError.invalidURL(currentURL) }
            let urlRequest = request.urlRequest(url: url, method: method, includeBody: includeBody,
                                                cookieHeader: cookieJar.cookieHeader(forURL: currentURL))
            let hop = try http.send(urlRequest)
            let headers = Self.headerDictionary(hop.response)
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
            for cookie in cookies { receivedCookies[cookie.name] = cookie.value }
            if source.enabledCookieJar {
                cookieJar.absorb(cookies, defaultHost: url.host?.lowercased())
            }
            let status = hop.response.statusCode
            if request.followRedirects, [301, 302, 303, 307, 308].contains(status),
               let location = Self.header("Location", in: headers), !location.isEmpty {
                let next = LegadoURLResolver.absolute(location, base: currentURL)
                currentURL = LegadoURLEncoder.encodeURL(next, encoding: .utf8)
                if status == 303 || ((status == 301 || status == 302) && method == "POST") {
                    method = "GET"
                    includeBody = false
                }
                continue
            }
            let body = LegadoResponseDecoder.decode(hop.data, contentType: Self.header("Content-Type", in: headers),
                                                    declaredCharset: request.charset)
            return LegadoHTTPResponse(requestURL: request.url, finalURL: hop.response.url?.absoluteString ?? currentURL,
                                      statusCode: status, headers: headers, cookies: receivedCookies, body: body,
                                      data: hop.data)
        }
        throw LegadoEngineError.network(url: request.url, message: "Chuyển hướng quá nhiều lần")
    }

    // MARK: - WebView (§4.4)

    private func performWebView(_ request: LegadoHTTPRequest, webJs: String?, htmlString: String? = nil) throws -> LegadoHTTPResponse {
        guard let url = URL(string: request.url) else { throw LegadoEngineError.invalidURL(request.url) }
        let urlRequest = request.urlRequest(url: url, cookieHeader: nil)
        let userAgent = request.header("User-Agent") ?? LegadoHTTPClient.webViewUserAgent
        var resourcePattern: NSRegularExpression?
        if let pattern = request.sourceRegex {
            resourcePattern = try? NSRegularExpression(pattern: pattern)
            if resourcePattern == nil {
                diagnostics.record(.ruleSyntax, "sourceRegex không biên dịch được, bỏ qua: \(pattern.prefix(120))")
            }
        }
        let result: LegadoWebViewFetcher.Result
        do {
            result = try LegadoWebViewFetcher.load(
                request: urlRequest, htmlString: htmlString, userAgent: userAgent, delay: request.webViewDelay,
                webJs: webJs, timeout: 30, cookies: cookieJar.httpCookies(forURL: request.url), cancellation: cancellation,
                sourceRegex: resourcePattern
            )
        } catch {
            if error is CancellationError || cancellation.isCancelled { throw CancellationError() }
            throw Self.engineError(error, url: request.url)
        }
        cookieJar.absorb(result.cookies, defaultHost: url.host?.lowercased())
        return LegadoHTTPResponse(requestURL: request.url, finalURL: result.finalURL, statusCode: 200, headers: [:],
                                  cookies: [:], body: result.body, data: Data(result.body.utf8))
    }

    /// `java.webView(html, url, js)`: `html` không rỗng ⇒ nạp chuỗi HTML với URL nền `url`.
    /// `sourceRegex` khác `nil` ⇒ thân = URL tài nguyên đầu tiên khớp (`java.webViewGetSource`, `getStrResponse`).
    func loadInWebView(url: String, htmlString: String?, script: String?, sourceRegex: String? = nil) throws -> LegadoHTTPResponse {
        var request = LegadoHTTPRequest(url: url)
        request.headers = [(name: "User-Agent", value: LegadoHTTPClient.webViewUserAgent)]
        request.useWebView = true
        request.sourceRegex = sourceRegex
        try rateLimiter?.acquire(cancellation: cancellation)
        return try recordingRequest(request) {
            try performWebView(request, webJs: script, htmlString: htmlString)
        }
    }

    // MARK: - Header nguồn (§3.10)

    /// Header nguồn tính **mỗi request**: JS (`@js:`/`<js>`), JSON lenient (giá trị có `{{…}}` được thay lúc gửi),
    /// hoặc dạng khác (dòng `Khoá: Giá trị`, UA trần). Khoá `proxy` bị bỏ (đợt 1).
    func sourceHeaders(baseUrl: String?) throws -> [(name: String, value: String)] {
        let raw = source.header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        guard !isComputingSourceHeaders else {
            diagnostics.record(.info, "Header nguồn gọi lại request trong lúc đang tính header: request đó không kèm header nguồn")
            return []
        }
        isComputingSourceHeaders = true
        defer { isComputingSourceHeaders = false }
        let base = baseUrl ?? sourceBase
        let lower = raw.lowercased()
        var pairs: [(name: String, value: String)]
        if lower.hasPrefix("@js:") || lower.hasPrefix("<js>") {
            var code = String(raw.dropFirst(4))
            if lower.hasPrefix("<js>"), let close = code.range(of: "</js>", options: .caseInsensitive) {
                code = String(code[..<close.lowerBound])
            }
            let value = try evaluateScript(code, result: nil, baseUrl: base, src: nil)
            switch value {
            case .json(let value): pairs = LegadoHeaderParser.pairs(from: value)
            case .string(let text): pairs = LegadoHeaderParser.pairs(fromText: text)
            default: pairs = []
            }
        } else {
            pairs = LegadoHeaderParser.pairs(fromText: raw)
            if pairs.contains(where: { LegadoRuleScanner.containsPlaceholder($0.value) }) {
                let templateAnalyzer = analyzer(node: .string(""), baseUrl: base, src: nil)
                var rendered: [(name: String, value: String)] = []
                for pair in pairs {
                    if LegadoRuleScanner.containsPlaceholder(pair.value) {
                        let value = try templateAnalyzer.renderTemplate(pair.value, content: templateAnalyzer.content,
                                                                        mode: .raw).text
                        rendered.append((name: pair.name, value: value))
                    } else {
                        rendered.append(pair)
                    }
                }
                pairs = rendered
            }
        }
        if pairs.contains(where: { $0.name.caseInsensitiveCompare("proxy") == .orderedSame }) {
            diagnostics.record(.unsupported, "proxy trong header nguồn")
            pairs = LegadoHeaderParser.removing("proxy", from: pairs)
        }
        return pairs
    }

    // MARK: - Tiện ích

    static func headerDictionary(_ response: HTTPURLResponse) -> [String: String] {
        var output: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            output[String(describing: key)] = String(describing: value)
        }
        return output
    }

    static func header(_ name: String, in headers: [String: String]) -> String? {
        headers.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame })?.value
    }

    static func engineError(_ error: Error, url: String) -> Error {
        if error is CancellationError || error is LegadoEngineError { return error }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return LegadoEngineError.timeout(url: url)
        }
        return LegadoEngineError.network(url: url, message: error.localizedDescription)
    }
}
