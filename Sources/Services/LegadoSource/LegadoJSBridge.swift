import Foundation
import JavaScriptCore
import SwiftSoup

/// Cài đối tượng `java` — bộ hàm mà script nguồn Legado gọi.
///
/// Legado có **102** hàm (`JsExtensions.kt`); đo trên corpus 2 746 nguồn thì ~25 hàm phủ gần hết lượt
/// dùng, nên chỉ làm nhóm đó. Hàm ngoài phạm vi vẫn được đăng ký nhưng trả rỗng **và** ghi
/// `LegadoUnsupportedFeature`, để nguồn hỏng có lý do rõ ràng thay vì `undefined is not a function`.
public enum LegadoJSBridge {

    public static func install(on context: JSContext, runtime: LegadoJSRuntime) {
        let java = JSValue(newObjectIn: context)
        installNetwork(java, context: context, runtime: runtime)
        installDigest(java, runtime: runtime)
        installEncoding(java, runtime: runtime)
        installVariables(java, runtime: runtime)
        installText(java, runtime: runtime)
        installParsing(java, runtime: runtime)
        installUnsupported(java, runtime: runtime)
        context.setObject(java, forKeyedSubscript: "java" as NSCopying & NSObjectProtocol)

        // Một số nguồn gọi trực tiếp `md5Encode(...)` không qua `java.`
        context.setObject(java?.objectForKeyedSubscript("md5Encode"),
                          forKeyedSubscript: "md5Encode" as NSCopying & NSObjectProtocol)
    }

    // MARK: - Mạng

    private static func installNetwork(_ java: JSValue?, context: JSContext, runtime: LegadoJSRuntime) {
        /// `java.ajax(url)` — trả về **thân** phản hồi dạng chuỗi.
        let ajax: @convention(block) (String?) -> String = { urlString in
            guard let urlString, !urlString.isEmpty else { return "" }
            return blockingBody(urlString, runtime: runtime) ?? ""
        }
        java?.setObject(ajax, forKeyedSubscript: "ajax" as NSCopying & NSObjectProtocol)

        /// `java.connect(url[, header])` — trả về object có `.body()`, `.code()`, `.header(name)`.
        let connect: @convention(block) (String?, String?) -> JSValue? = { urlString, headerJSON in
            guard let urlString, !urlString.isEmpty else { return nil }
            let extraHeaders = LegadoJSON.headerMap(headerJSON)
            let response = blockingResponse(urlString, runtime: runtime, extraHeaders: extraHeaders)
            return makeResponseObject(response, in: context)
        }
        java?.setObject(connect, forKeyedSubscript: "connect" as NSCopying & NSObjectProtocol)

        let get: @convention(block) (String?, String?) -> JSValue? = { urlString, headerJSON in
            guard let urlString else { return nil }
            let extraHeaders = LegadoJSON.headerMap(headerJSON)
            let response = blockingResponse(urlString, runtime: runtime, extraHeaders: extraHeaders)
            return makeResponseObject(response, in: context)
        }
        java?.setObject(get, forKeyedSubscript: "get" as NSCopying & NSObjectProtocol)

        let post: @convention(block) (String?, String?, String?) -> JSValue? = { urlString, body, headerJSON in
            guard let urlString else { return nil }
            let extraHeaders = LegadoJSON.headerMap(headerJSON)
            let response = blockingResponse(
                urlString,
                runtime: runtime,
                extraHeaders: extraHeaders,
                method: "POST",
                body: body
            )
            return makeResponseObject(response, in: context)
        }
        java?.setObject(post, forKeyedSubscript: "post" as NSCopying & NSObjectProtocol)

        let head: @convention(block) (String?, String?) -> JSValue? = { urlString, headerJSON in
            guard let urlString else { return nil }
            let response = blockingResponse(
                urlString,
                runtime: runtime,
                extraHeaders: LegadoJSON.headerMap(headerJSON),
                method: "HEAD"
            )
            return makeResponseObject(response, in: context)
        }
        java?.setObject(head, forKeyedSubscript: "head" as NSCopying & NSObjectProtocol)

        let getCookie: @convention(block) (String?, String?) -> String = { urlString, _ in
            guard let urlString, let url = URL(string: urlString),
                  let cookies = HTTPCookieStorage.shared.cookies(for: url) else { return "" }
            return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
        java?.setObject(getCookie, forKeyedSubscript: "getCookie" as NSCopying & NSObjectProtocol)
    }

    private static func blockingBody(_ urlString: String, runtime: LegadoJSRuntime) -> String? {
        blockingResponse(urlString, runtime: runtime)?.body
    }

    private static func blockingResponse(
        _ urlString: String,
        runtime: LegadoJSRuntime,
        extraHeaders: [String: String] = [:],
        method: String? = nil,
        body: String? = nil
    ) -> LegadoHTTPResponse? {
        let scope = runtime.currentScope
        // Dùng header đã giải (kể cả khi nguồn khai `header` bằng `@js:`), không phải chuỗi thô.
        var headers = runtime.resolvedHeaderMap()
        for (name, value) in extraHeaders { headers[name] = value }

        var spec = LegadoUrlBuilder.build(
            rule: urlString,
            baseUrl: scope.baseUrl,
            sourceHeaders: headers,
            interpolate: { $0 }
        )
        if let method {
            spec = LegadoRequestSpec(
                url: spec.url,
                method: method,
                headers: spec.headers,
                body: body?.data(using: .utf8) ?? spec.body,
                charset: spec.charset ?? scope.charset,
                retry: spec.retry,
                requiresWebView: spec.requiresWebView
            )
        } else if spec.charset == nil, let charset = scope.charset {
            spec = LegadoRequestSpec(
                url: spec.url,
                method: spec.method,
                headers: spec.headers,
                body: spec.body,
                charset: charset,
                retry: spec.retry,
                requiresWebView: spec.requiresWebView
            )
        }

        if spec.requiresWebView {
            runtime.noteUnsupported(.webViewRule)
        }
        return LegadoHTTPClient.shared.sendBlocking(spec)
    }

    private static func makeResponseObject(
        _ response: LegadoHTTPResponse?,
        in context: JSContext
    ) -> JSValue? {
        let object = JSValue(newObjectIn: context)
        let bodyText = response?.body ?? ""
        let statusCode = response?.statusCode ?? 0
        let finalUrl = response?.finalUrl ?? ""
        let headers = response?.headers ?? [:]

        object?.setValue(bodyText, forProperty: "bodyText")
        object?.setValue(NSNumber(value: statusCode), forProperty: "statusCode")
        object?.setValue(finalUrl, forProperty: "url")

        let body: @convention(block) () -> String = { bodyText }
        object?.setObject(body, forKeyedSubscript: "body" as NSCopying & NSObjectProtocol)
        let code: @convention(block) () -> NSNumber = { NSNumber(value: statusCode) }
        object?.setObject(code, forKeyedSubscript: "code" as NSCopying & NSObjectProtocol)
        let header: @convention(block) (String?) -> String = { name in
            guard let name else { return "" }
            let lower = name.lowercased()
            for (key, value) in headers where key.lowercased() == lower { return value }
            return ""
        }
        object?.setObject(header, forKeyedSubscript: "header" as NSCopying & NSObjectProtocol)
        let raw: @convention(block) () -> String = { bodyText }
        object?.setObject(raw, forKeyedSubscript: "raw" as NSCopying & NSObjectProtocol)
        return object
    }
}
