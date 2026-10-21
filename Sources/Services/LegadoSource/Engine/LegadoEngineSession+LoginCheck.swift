import Foundation
import JavaScriptCore

/// `loginCheckJs` (spec §10.7): chạy sau mỗi request **luồng chính** (từ `fetch`), trước khi phân tích thân.
///
/// - `result` = đối tượng phản hồi (`body()`, `code()`, `url()`, `headers()`…); có thêm `java.ruleUrl`, `java.initUrl()`,
///   `java.getHeaderMap()`, `java.getStrResponse(js, sourceRegex)`, `java.getResponse()`.
/// - Trả đối tượng phản hồi ⇒ **thay** phản hồi gốc; trả chuỗi ⇒ thân mới (URL giữ nguyên); `undefined`/`null` ⇒ giữ.
///   Lỗi JS ⇒ giữ phản hồi gốc (đã ghi chẩn đoán).
/// - Request phát sinh bên trong (`java.connect`, `getStrResponse`) không kích hoạt lại `loginCheckJs`.
extension LegadoEngineSession {
    func runLoginCheck(_ code: String, response: LegadoHTTPResponse, request: LegadoHTTPRequest, ruleUrl: String,
                       baseUrl: String?, key: String?, page: Int?, webJs: String?) throws -> LegadoHTTPResponse {
        let savedKey = self.key
        let savedPage = self.page
        if let key { self.key = key }
        if let page { self.page = page }
        isRunningLoginCheck = true
        loginCheckContext = LegadoLoginCheckContext(ruleUrl: ruleUrl, baseUrl: baseUrl, key: key, page: page, webJs: webJs,
                                                    request: request)
        runtime.prepareLoginCheck(ruleUrl: ruleUrl)
        ruleFrames.append(RuleFrame(content: .string(response.body), baseUrl: response.finalURL, src: response.body))
        defer {
            ruleFrames.removeLast()
            runtime.finishLoginCheck()
            loginCheckContext = nil
            isRunningLoginCheck = false
            self.key = savedKey
            self.page = savedPage
        }
        var bindings = jsBindings(result: nil, baseUrl: request.url, src: response.body)
        bindings.responseResult = LegadoJSRuntime.responseJSON(response)
        let outcome = try runtime.evaluateRaw(code, bindings: bindings)
        guard outcome.error == nil else { return response }
        switch runtime.classifyLoginCheck(outcome.value) {
        case .unchanged:
            return response
        case .body(let text):
            var updated = response
            updated.body = text
            updated.data = Data(text.utf8)
            return updated
        case .response(let json):
            return Self.response(fromJSON: json, original: response)
        }
    }

    /// Đối tượng phản hồi JS (`{url, code, message, headers, cookies, body}`) → phản hồi của engine. Không đổi gì so với
    /// bản gốc ⇒ trả bản gốc (giữ byte thô).
    static func response(fromJSON json: LegadoEngineJSON, original: LegadoHTTPResponse) -> LegadoHTTPResponse {
        let url = json["url"]?.scalarString ?? ""
        let body = json["body"]?.scalarString ?? ""
        var code = original.statusCode
        if let number = json["code"]?.doubleValue, number.isFinite, abs(number) < 10_000 { code = Int(number) }
        let finalURL = url.isEmpty ? original.finalURL : url
        if finalURL == original.finalURL, code == original.statusCode, body == original.body { return original }
        var headers: [String: String] = [:]
        for entry in json["headers"]?.objectEntries ?? [] { headers[entry.key] = entry.value.scalarString }
        var cookies: [String: String] = [:]
        for entry in json["cookies"]?.objectEntries ?? [] { cookies[entry.key] = entry.value.scalarString }
        return LegadoHTTPResponse(requestURL: original.requestURL, finalURL: finalURL, statusCode: code,
                                  headers: headers, cookies: cookies, body: body, data: Data(body.utf8))
    }

    // MARK: - Hàm riêng của ngữ cảnh loginCheckJs

    /// `java.initUrl()`: dựng lại request từ rule URL (header nguồn + đăng nhập + cookie hiện tại).
    func loginCheckInitURL() throws {
        guard var context = loginCheckContext else { return }
        context.request = try buildRequest(context.ruleUrl, baseUrl: context.baseUrl, key: context.key, page: context.page)
        loginCheckContext = context
    }

    /// `java.getStrResponse(jsStr, sourceRegex)` (U44): gửi lại request đang dựng (header có thể đã sửa qua
    /// `java.getHeaderMap()`); `jsStr`/`sourceRegex` khác `nil` ⇒ nạp bằng WebView. Lỗi mạng ⇒ `nil` (mã 0).
    func loginCheckResend(headers: [(name: String, value: String)]?, script: String?, sourceRegex: String?) throws -> LegadoHTTPResponse? {
        guard let context = loginCheckContext else {
            throw LegadoJSNativeError("java.getStrResponse chỉ dùng được trong loginCheckJs")
        }
        var request = context.request
        if let headers { request.headers = headers }
        if script != nil || sourceRegex != nil {
            request.useWebView = true
            request.sourceRegex = sourceRegex
            request.timeout = 30
        }
        do {
            return try perform(request, webJs: script ?? context.webJs, allowHTTPError: true)
        } catch {
            if error is CancellationError || cancellation.isCancelled { throw CancellationError() }
            diagnostics.record(.network, "java.getStrResponse: \(error.localizedDescription)")
            return nil
        }
    }
}
