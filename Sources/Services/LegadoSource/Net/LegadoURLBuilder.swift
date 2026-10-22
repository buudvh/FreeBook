import Foundation

/// Thuật toán dựng request từ một "rule URL" (spec §3.2), dùng chung cho `searchUrl`, mục khám phá, trường URL được
/// gửi đi và URL truyền vào `java.ajax`/`java.connect`. Nguồn Legado **không** đi qua `JSExecutor.cleanAndResolveUrl`.
///
/// 1. JS sinh URL (`@js:`/`<js>`): phân đoạn chữ cộng dồn, phân đoạn JS nhận `result` = chuỗi tích luỹ — placeholder
///    trong **mã JS** không được thay trước.
/// 2. Danh sách trang `<a,b,…>`. 3. Thay `{{…}}` (cả trong khối option). 4. Tách option `,{…}` (lenient).
/// 5. Option `js`. 6. Ghép URL tuyệt đối + mã hoá theo `charset`. 7. Gộp header: mặc định < nguồn < option < `java.headerMap`.
struct LegadoURLBuilder {
    let session: LegadoEngineSession

    func build(_ rule: String, baseUrl: String, page: Int, content: LegadoContentNode?) throws -> LegadoHTTPRequest {
        // Mốc chẩn đoán: JS sinh URL lỗi chỉ cho `.null` (§6.1) — nếu URL không dựng được thì báo lỗi JS đó (bước 6).
        let diagnosticsMark = session.diagnostics.entries.count
        // 1. JS sinh URL.
        var accumulated = ""
        for segment in LegadoRuleScanner.segments(rule) {
            switch segment {
            case .rule(let text):
                accumulated += text
            case .js(let code):
                let value = try session.evaluateScript(code, result: .string(accumulated), baseUrl: baseUrl, src: nil)
                accumulated = Self.urlText(from: value)
            }
        }
        // 2. Danh sách trang.
        accumulated = Self.applyPageList(accumulated, page: page)

        // 3 + 4. Tách option ở chuỗi thô (ngoài `{{…}}`), thay placeholder từng phần, rồi parse option.
        let split = LegadoURLResolver.splitOption(accumulated)
        let templateSource = session.analyzer(node: content ?? .string(""), baseUrl: baseUrl, src: nil)
        templateSource.substitutesPlaceholdersInJS = false
        var urlPart = try render(split.url, with: templateSource)
        var option: LegadoURLOption?
        var renderedOption: String?
        if let optionText = split.option {
            let rendered = try render(optionText, with: templateSource)
            option = LegadoURLOption.parse(rendered)
            if option == nil {
                session.diagnostics.record(.ruleSyntax, "Khối option URL không đọc được: \(rendered.prefix(120))")
                urlPart += "," + rendered
            } else {
                renderedOption = rendered
            }
        }

        // URL `data:` (spec §13.1): giữ nguyên chuỗi gồm khối option (nguồn đọc lại option từ `baseUrl`).
        let dataCandidate = urlPart.trimmingCharacters(in: .whitespacesAndNewlines)
        if LegadoDataURL.isDataURL(dataCandidate) {
            var request = LegadoHTTPRequest(url: renderedOption.map { dataCandidate + "," + $0 } ?? dataCandidate)
            request.type = option?.type
            return request
        }

        // 7 (phần đầu). Header: mặc định < nguồn < đăng nhập (§10.6) < option.
        var headers: [(name: String, value: String)] = [(name: "User-Agent", value: LegadoHTTPClient.defaultUserAgent)]
        let sourcePairs = try session.sourceHeaders(baseUrl: baseUrl)
        headers = LegadoHeaderParser.merge(headers, sourcePairs)
        let loginTarget = LegadoURLResolver.absolute(dataCandidate, base: baseUrl)
        headers = LegadoHeaderParser.merge(headers, session.loginHeaders(forURL: loginTarget, pageURL: baseUrl))
        if let option {
            headers = LegadoHeaderParser.merge(headers, option.headers)
        }

        // 5. Option `js`: đọc/sửa `java.url`, `java.headerMap`.
        if let script = option?.js {
            let bindings = session.jsBindings(result: .string(urlPart), baseUrl: baseUrl, src: nil)
            let outcome = try session.runtime.evaluateOptionScript(script, url: urlPart, headers: headers, bindings: bindings)
            urlPart = outcome.url
            headers = outcome.headers
        }

        // 6. URL tuyệt đối + mã hoá.
        let trimmedURL = urlPart.trimmingCharacters(in: .whitespacesAndNewlines)
        if LegadoDataURL.isDataURL(trimmedURL) {
            var request = LegadoHTTPRequest(url: trimmedURL)
            request.type = option?.type
            return request
        }
        let resolved = LegadoURLResolver.absolute(trimmedURL, base: baseUrl)
        guard LegadoURLResolver.hasHTTPScheme(resolved) else {
            throw unresolvedURLError(trimmedURL, diagnosticsMark: diagnosticsMark)
        }
        let encoding = LegadoCharset.requestEncoding(named: option?.charset)
        var request = LegadoHTTPRequest(url: LegadoURLEncoder.encodeURL(resolved, encoding: encoding))
        request.headers = headers
        request.charset = option?.charset
        request.type = option?.type

        // Phương thức & thân (§3.9): có `body` mà thiếu `method` ⇒ POST; GET/HEAD bỏ thân.
        let method = option?.method ?? (option?.body != nil ? "POST" : "GET")
        request.method = method
        if method != "GET" && method != "HEAD", let body = option?.body {
            let encoded = Self.bodyData(body, encoding: encoding, charsetName: option?.charset)
            request.body = encoded.data
            if request.header("Content-Type") == nil {
                request.setHeader("Content-Type", encoded.contentType)
            }
        }
        request.useWebView = option?.webView ?? false
        request.webViewDelay = max(0, (option?.webViewDelayTime ?? 0) / 1000)
        if let retry = option?.retry { request.retryCount = max(0, min(retry, 5)) }
        request.timeout = request.useWebView ? 30 : 15
        return request
    }

    private func render(_ text: String, with analyzer: LegadoRuleAnalyzer) throws -> String {
        guard LegadoRuleScanner.containsPlaceholder(text) else { return text }
        return try analyzer.renderTemplate(text, content: analyzer.content, mode: .raw).text
    }

    /// URL không thành tuyệt đối. JS dựng URL (`@js:`, `{{…}}`, option `js`) vừa lỗi ⇒ báo đúng lỗi đó (hàm chưa hỗ trợ
    /// trước, rồi lỗi JS) thay vì "không có URL gốc". Còn lại: URL rỗng ⇒ URL không hợp lệ; URL tương đối mà nguồn không
    /// có URL gốc (§1.4) ⇒ `missingBaseURL`.
    private func unresolvedURLError(_ url: String, diagnosticsMark: Int) -> LegadoEngineError {
        let fresh = session.diagnostics.entries.dropFirst(diagnosticsMark)
        // Mục "bỏ qua, chỉ ghi vào bản sao" không làm hỏng luồng — không phải nguyên nhân.
        if let feature = fresh.first(where: { $0.kind == .unsupported && !$0.message.contains("bỏ qua") }) {
            return .unsupportedSyntax(feature.message)
        }
        if let script = fresh.first(where: { $0.kind == .javaScript }) {
            return .javaScript(script.message)
        }
        return url.isEmpty ? .invalidURL("(rỗng sau khi dựng)") : .missingBaseURL(url)
    }

    // MARK: - Bước phụ

    /// Kết quả JS sinh URL → chuỗi. Object có khoá `url` ⇒ `url` + option là các khoá còn lại (§3.3, đề xuất).
    static func urlText(from value: LegadoContentNode) -> String {
        if case .json(let json) = value, let entries = json.objectEntries, let url = json["url"] {
            let rest = entries.filter { $0.key != "url" }
            if rest.isEmpty { return url.scalarString }
            return url.scalarString + "," + LegadoEngineJSON.object(rest).compactText
        }
        return value.finalString
    }

    /// `<a,b,c>`: trang N dùng mục thứ N (đếm từ 1); N vượt số mục ⇒ mục cuối (U12). Bỏ qua `<js>`, thẻ, vùng `{{…}}`.
    static func applyPageList(_ text: String, page: Int) -> String {
        guard text.contains("<"), text.contains(",") else { return text }
        let bytes = Array(text.utf8)
        var output: [UInt8] = []
        var index = 0
        while index < bytes.count {
            if bytes[index] == LegadoRuleScanner.brace, index + 1 < bytes.count, bytes[index + 1] == LegadoRuleScanner.brace,
               let end = LegadoRuleScanner.balancedEnd(bytes, from: index) {
                output.append(contentsOf: bytes[index..<end])
                index = end
                continue
            }
            if bytes[index] == UInt8(ascii: "<"), let close = bytes[(index + 1)...].firstIndex(of: UInt8(ascii: ">")) {
                let inner = LegadoRuleScanner.string(bytes, index + 1, close)
                let lower = inner.lowercased()
                if inner.contains(","), !inner.contains("<"), !lower.hasPrefix("js"), !lower.hasPrefix("/") {
                    let items = inner.components(separatedBy: ",")
                    let position = min(max(page, 1), items.count) - 1
                    output.append(contentsOf: Array(items[position].utf8))
                    index = close + 1
                    continue
                }
            }
            output.append(bytes[index])
            index += 1
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// Thân request (§3.8–§3.9): object/mảng ⇒ JSON UTF-8; chuỗi văn bản JSON ⇒ gửi nguyên (theo charset);
    /// chuỗi form ⇒ mã hoá form theo charset. Content-Type mặc định: object ⇒ JSON, chuỗi ⇒ form (U8).
    static func bodyData(_ body: LegadoEngineJSON, encoding: String.Encoding, charsetName: String?) -> (data: Data, contentType: String) {
        let formType = "application/x-www-form-urlencoded" + (charsetName.map { "; charset=\($0)" } ?? "")
        switch body {
        case .object, .array:
            return (Data(body.compactText.utf8), "application/json")
        default:
            let text = body.scalarString
            if LegadoEngineJSONParser.parseContainer(text) != nil {
                return (Data(LegadoCharset.bytes(of: text, encoding: encoding)), formType)
            }
            return (Data(LegadoURLEncoder.encodeForm(text, encoding: encoding).utf8), formType)
        }
    }
}
