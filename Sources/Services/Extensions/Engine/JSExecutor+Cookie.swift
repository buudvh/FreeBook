import Foundation
import JavaScriptCore

/// Cookie của tiện ích theo hợp đồng: `localCookie` là cookie của tên miền `source`, **dùng chung với `fetch`** — nên đọc/ghi
/// thẳng `HTTPCookieStorage.shared`, đúng kho mà `URLSession.shared` của `_nativeSyncFetch` gửi/nhận.
/// - `getCookie(url?)`: header `Cookie` cho URL http(s) truyền vào, không truyền ⇒ cho URL `source`; không có ⇒ `""`.
/// - `setCookie(s)`: lưu cho host `source`. Mọi đoạn sau đoạn đầu đều là thuộc tính cookie (`path`, `domain`, `expires`,
///   `max-age`, `secure`, `httponly`, `samesite`) ⇒ đọc như một dòng `Set-Cookie`; ngược lại là danh sách `a=1; b=2`, mỗi
///   cặp một cookie phiên với path `/`.
/// - Trước mỗi lượt chạy (`callAsync`), cookie WebKit của tên miền `source` (nơi người dùng đăng nhập) được chép sang kho
///   này — `ExtensionCookieSync`.
/// - `response.request.headers` của `fetch` có header thật sự gửi đi, kể cả `Cookie` (`sentRequestHeaders`).
///
/// Không log giá trị cookie.
extension JSExecutor {
    private static let setCookieAttributes: Set<String> = [
        "path", "domain", "expires", "max-age", "secure", "httponly", "samesite"
    ]

    /// `http_should_handle_cookies` của tiện ích (bool, hoặc chuỗi `"true"`/`"false"`); không khai ⇒ bật.
    internal var cookieHandlingEnabled: Bool {
        if let flag = injectedConfigs["http_should_handle_cookies"] as? Bool { return flag }
        if let text = injectedConfigs["http_should_handle_cookies"] as? String { return text.lowercased() == "true" }
        return true
    }

    /// Đầu `callAsync`: chép cookie WebKit của tên miền `source` sang `URLSession` khi kho WebKit đã đổi kể từ lần chép
    /// trước. Chạy cả khi tiện ích tắt cookie hệ thống: `fetch` khi đó không tự gửi, nhưng `localCookie.getCookie()` vẫn
    /// cần thấy phiên đăng nhập để script tự gắn.
    internal func syncSourceCookiesBeforeRun() async {
        guard let source = Self.sourceURL(localPath: localPath) else { return }
        await ExtensionCookieSync.shared.syncBeforeRun(sourceURL: source)
    }

    /// Cài `_nativeCookieGet` / `_nativeCookieSet` (polyfill `localCookie` ở `JSExtensionStorageBridge`). Tra `source` lúc
    /// gọi — người dùng có thể sửa `source` ở màn Cấu hình.
    internal func installCookieBridge() {
        let localPath = self.localPath
        let getBlock: @convention(block) (String) -> String = { urlString in
            guard let target = JSExecutor.httpURL(urlString) ?? JSExecutor.sourceURL(localPath: localPath),
                  let cookies = HTTPCookieStorage.shared.cookies(for: target), !cookies.isEmpty else { return "" }
            return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] ?? ""
        }
        context.setObject(getBlock, forKeyedSubscript: "_nativeCookieGet" as NSCopying & NSObjectProtocol)

        let setBlock: @convention(block) (String) -> Void = { cookieString in
            guard let source = JSExecutor.sourceURL(localPath: localPath) else {
                AppLogger.shared.log("❌ [JSCookie] setCookie bị bỏ qua: tiện ích không có source http(s)")
                return
            }
            let cookies = JSExecutor.parseCookies(cookieString, for: source)
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
        context.setObject(setBlock, forKeyedSubscript: "_nativeCookieSet" as NSCopying & NSObjectProtocol)
    }

    /// Header thật sự đi kèm request (`response.request.headers`): mọi header đặt trên `URLRequest` (header của script,
    /// `User-Agent`) + `Cookie`. `URLSession` gắn cookie trong kho **bên dưới** `URLRequest` (không có trong
    /// `allHTTPHeaderFields`) nên tự tính từ `HTTPCookieStorage.shared` — gọi ngay trước khi gửi. Script tự truyền `Cookie`
    /// ⇒ giữ đúng bản đó.
    internal static func sentRequestHeaders(for request: URLRequest) -> [String: String] {
        var headers = request.allHTTPHeaderFields ?? [:]
        let hasOwnCookie = headers.keys.contains { $0.caseInsensitiveCompare("Cookie") == .orderedSame }
        guard !hasOwnCookie, request.httpShouldHandleCookies, let url = request.url,
              let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty,
              let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] else { return headers }
        headers["Cookie"] = cookieHeader
        return headers
    }

    // MARK: - Phụ trợ

    /// URL `source` (http/https) của tiện ích; không có ⇒ `nil`.
    private static func sourceURL(localPath: String?) -> URL? {
        guard let localPath, let raw = ExtensionHostResolver.sourceUrl(localPath: localPath) else { return nil }
        return httpURL(raw)
    }

    /// URL http(s) tuyệt đối có host; khác (rỗng, tương đối, scheme lạ) ⇒ `nil`.
    private static func httpURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ExtensionCookieSync.host(of: url) != nil else { return nil }
        return url
    }

    /// Chuỗi của `setCookie` → cookie cho `source` (xem chú thích của extension).
    private static func parseCookies(_ raw: String, for source: URL) -> [HTTPCookie] {
        let segments = raw.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = segments.first else { return [] }
        let attributes = segments.dropFirst()
        let isSetCookieLine = first.contains("=") && !attributes.isEmpty && attributes.allSatisfy { segment in
            let name = segment.split(separator: "=", maxSplits: 1).first.map { String($0) } ?? segment
            return setCookieAttributes.contains(name.trimmingCharacters(in: .whitespaces).lowercased())
        }
        if isSetCookieLine {
            return HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": raw], for: source)
        }
        guard let host = source.host else { return [] }
        return segments.compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard parts.count == 2, !name.isEmpty else { return nil }
            return HTTPCookie(properties: [
                .name: name,
                .value: parts[1].trimmingCharacters(in: .whitespaces),
                .domain: host,
                .path: "/"
            ])
        }
    }
}
