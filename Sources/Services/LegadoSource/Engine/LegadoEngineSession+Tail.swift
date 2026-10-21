import Foundation

/// Phần đuôi đợt 2/3 ở phía phiên (spec §13.3, §13.9, §14.8): hook làm mới mục lục, `Jsoup.connect`,
/// `java.webViewGetSource`/`webViewGetOverrideUrl`, font tải qua mạng.
extension LegadoEngineSession {
    // MARK: - §13.3 java.refreshTocUrl / reGetBook

    /// `java.refreshTocUrl()` (cũng là `refreshBookUrl`/`refreshBookInfo`, U52): gọi `onRefreshTocUrl` do luồng đặt khi
    /// chạy `preUpdateJs`/`ruleBookInfo.init`; không có hook ⇒ cảnh báo, không làm gì. Hook lỗi ⇒ giữ `tocUrl` cũ + log.
    func jsRefreshTocUrl() throws {
        guard let hook = onRefreshTocUrl else {
            diagnostics.record(.info, "java.refreshTocUrl ngoài preUpdateJs/ruleBookInfo.init — bỏ qua")
            return
        }
        try runHook(hook, name: "java.refreshTocUrl")
    }

    /// `java.reGetBook()`: gọi `onReGetBook`; không có hook ⇒ cảnh báo, không làm gì.
    func jsReGetBook() throws {
        guard let hook = onReGetBook else {
            diagnostics.record(.info, "java.reGetBook ngoài preUpdateJs/ruleBookInfo.init — bỏ qua")
            return
        }
        try runHook(hook, name: "java.reGetBook")
    }

    private func runHook(_ hook: (LegadoEngineSession) throws -> Void, name: String) throws {
        do {
            try hook(self)
        } catch {
            if error is CancellationError || cancellation.isCancelled { throw CancellationError() }
            diagnostics.record(.info, "\(name) lỗi, giữ giá trị cũ: \(error.localizedDescription)")
        }
    }

    // MARK: - §13.9 org.jsoup.Jsoup.connect

    /// Request của `Connection` giả lập: cùng client của phiên (kho cookie, rate limiter); header = UA mặc định + header
    /// JS tự đặt, **không** gắn header nguồn/đăng nhập (U55). Lỗi mạng ⇒ `nil` + thông báo.
    func jsoupRequest(_ spec: LegadoEngineJSON) throws -> (response: LegadoHTTPResponse?, error: String?) {
        let rawURL = spec["url"]?.scalarString ?? ""
        var target = LegadoURLResolver.absolute(rawURL, base: currentFrameBaseUrl ?? sourceBase)
        let method = (spec["method"]?.scalarString ?? "GET").uppercased()
        var formPairs: [String] = []
        for item in spec["data"]?.arrayValue ?? [] {
            guard let pair = item.arrayValue, pair.count >= 2 else { continue }
            let name = LegadoURLEncoder.encodeComponent(pair[0].scalarString, encoding: .utf8)
            formPairs.append(name + "=" + LegadoURLEncoder.encodeComponent(pair[1].scalarString, encoding: .utf8))
        }
        let form = formPairs.joined(separator: "&")
        if !form.isEmpty, method == "GET" || method == "HEAD" {
            target += (target.contains("?") ? "&" : "?") + form
        }
        guard LegadoURLResolver.hasHTTPScheme(target) else { throw LegadoEngineError.invalidURL(rawURL) }
        var request = LegadoHTTPRequest(url: LegadoURLEncoder.encodeURL(target, encoding: .utf8))
        request.method = method
        var headers: [(name: String, value: String)] = [(name: "User-Agent", value: LegadoHTTPClient.defaultUserAgent)]
        if let custom = spec["headers"] { headers = LegadoHeaderParser.merge(headers, LegadoHeaderParser.pairs(from: custom)) }
        let cookies = (spec["cookies"]?.objectEntries ?? []).map { "\($0.key)=\($0.value.scalarString)" }
        if !cookies.isEmpty { headers = LegadoHeaderParser.merge(headers, [(name: "Cookie", value: cookies.joined(separator: "; "))]) }
        request.headers = headers
        if method != "GET", method != "HEAD" {
            if let body = spec["body"], !body.isNull {
                request.body = Data(body.scalarString.utf8)
            } else if !form.isEmpty {
                request.body = Data(form.utf8)
            }
            if request.body != nil, request.header("Content-Type") == nil {
                request.setHeader("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
            }
        }
        if let milliseconds = spec["timeout"]?.doubleValue, milliseconds.isFinite, milliseconds > 0 {
            request.timeout = min(milliseconds / 1000, 120)
        }
        if let follow = spec["followRedirects"], case .bool(let flag) = follow { request.followRedirects = flag }
        do {
            let response = try perform(request, allowHTTPError: true)
            return (response, nil)
        } catch {
            if error is CancellationError || cancellation.isCancelled { throw CancellationError() }
            diagnostics.record(.network, "Jsoup.connect \(rawURL.prefix(160)): \(error.localizedDescription)")
            return (nil, error.localizedDescription)
        }
    }

    // MARK: - §14.8 webViewGetSource / webViewGetOverrideUrl

    /// Nạp trang (hoặc chuỗi HTML với URL nền `url`) bằng WebView ẩn, trả URL request đầu tiên (điều hướng, XHR, fetch,
    /// media) khớp **toàn chuỗi** `pattern`; hết giờ/lỗi ⇒ `""`. Bản `OverrideUrl` dùng chung lõi (không chặn điều hướng).
    func jsWebViewResource(html: String?, url: String?, pattern: String) throws -> String {
        let target = LegadoURLResolver.absolute(url ?? "", base: currentFrameBaseUrl ?? sourceBase)
        let pageURL = target.isEmpty ? sourceBase : target
        let trimmedHTML = html?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        do {
            let response = try loadInWebView(url: LegadoURLEncoder.encodeURL(pageURL, encoding: .utf8),
                                             htmlString: trimmedHTML.isEmpty ? nil : html, script: nil,
                                             sourceRegex: pattern)
            return response.body
        } catch {
            if error is CancellationError || cancellation.isCancelled { throw CancellationError() }
            diagnostics.record(.network, "java.webViewGetSource \(pageURL.prefix(160)): \(error.localizedDescription)")
            return ""
        }
    }

    // MARK: - §14.1 font qua mạng

    /// Byte font ở `url` (qua client của nguồn), đệm bền trong thư mục tệp của nguồn theo URL; lỗi ⇒ `nil`.
    func fontData(url: String) throws -> Data? {
        let files = sourceFiles
        let name = "fonts/" + Self.md5Hex16(url) + ".font"
        if let cached = files.read(name), !cached.isEmpty { return cached }
        do {
            let request = try buildRequest(url, baseUrl: currentFrameBaseUrl)
            let response = try perform(request)
            guard !response.data.isEmpty, response.data.count <= LegadoSourceFiles.maxDownloadBytes else { return nil }
            _ = try? files.write(response.data, to: name)
            return response.data
        } catch {
            if error is CancellationError || cancellation.isCancelled { throw CancellationError() }
            diagnostics.record(.network, "java.queryTTF \(url.prefix(160)): \(error.localizedDescription)")
            return nil
        }
    }
}
