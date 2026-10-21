import Foundation

/// `java.ajax/ajaxAll/connect/get/post/head/webView` (spec §6.4.1). Mọi request đi qua phiên (rate limiter, cookie,
/// header nguồn). `ajax` trả thân bất kể mã HTTP, lỗi mạng ⇒ `""` (U18); `connect`/`get`/`post`/`head` trả đối tượng
/// phản hồi để JS tự xử lý mã.
extension LegadoJSRuntime {
    func nativeNetwork(_ command: String, _ arguments: LegadoJSArguments, _ session: LegadoEngineSession) throws -> String? {
        switch command {
        case "ajax":
            return try session.jsAjax(text(of: arguments[0]), timeoutMs: arguments.number(1))
        case "ajaxAll":
            let urls: [String] = arguments[0].arrayValue?.map { text(of: $0) }
                ?? arguments[0]["$arr"]?.arrayValue?.map { text(of: $0) } ?? []
            var responses: [LegadoEngineJSON] = []
            for url in urls {
                let response = try session.jsConnect(url, headers: nil)
                responses.append(Self.responseJSON(response))
            }
            return LegadoEngineJSON.array(responses).compactText
        case "connect":
            let response = try session.jsConnect(text(of: arguments[0]), headers: arguments.plainString(1))
            return Self.responseJSON(response).compactText
        case "httpGet":
            let response = try session.jsDirectRequest(method: "GET", url: text(of: arguments[0]), body: nil,
                                                       headers: arguments.plainString(1))
            return Self.responseJSON(response).compactText
        case "httpPost":
            let response = try session.jsDirectRequest(method: "POST", url: text(of: arguments[0]),
                                                       body: text(of: arguments[1]), headers: arguments.plainString(2))
            return Self.responseJSON(response).compactText
        case "httpHead":
            let response = try session.jsDirectRequest(method: "HEAD", url: text(of: arguments[0]), body: nil,
                                                       headers: arguments.plainString(1))
            return Self.responseJSON(response).compactText
        case "webView":
            return try session.jsWebView(html: arguments.plainString(0), url: arguments.plainString(1),
                                         script: arguments.plainString(2))
        default:
            return nil
        }
    }

    /// Đối tượng phản hồi cho bootstrap: `{url, code, message, headers, cookies, body}`; lỗi mạng ⇒ mã 0, thân rỗng.
    static func responseJSON(_ response: LegadoHTTPResponse?) -> LegadoEngineJSON {
        guard let response else {
            return .object([
                (key: "url", value: .string("")), (key: "code", value: .fromNumber(0)),
                (key: "message", value: .string("")), (key: "headers", value: .object([])),
                (key: "cookies", value: .object([])), (key: "body", value: .string(""))
            ])
        }
        let headers = response.headers.sorted { $0.key < $1.key }.map { (key: $0.key, value: LegadoEngineJSON.string($0.value)) }
        let cookies = response.cookies.sorted { $0.key < $1.key }.map { (key: $0.key, value: LegadoEngineJSON.string($0.value)) }
        return .object([
            (key: "url", value: .string(response.finalURL)),
            (key: "code", value: .fromNumber(Double(response.statusCode))),
            (key: "message", value: .string(response.message)),
            (key: "headers", value: .object(headers)),
            (key: "cookies", value: .object(cookies)),
            (key: "body", value: .string(response.body))
        ])
    }
}
