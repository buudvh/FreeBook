import Foundation

/// Một cookie trong kho cookie theo nguồn (`LegadoCookieJar`). Tên miền không có dấu chấm đầu, viết thường.
/// Bỏ qua `path`/`secure`: kho chỉ phục vụ request của chính nguồn, gửi theo tên miền (spec §4.2).
struct LegadoStoredCookie: Codable, Equatable {
    var domain: String
    var name: String
    var value: String
    /// Giây epoch; `nil` = cookie phiên (vẫn lưu, như tài liệu nói kho tự lưu `Set-Cookie`).
    var expires: Double?

    func isExpired(at now: Date = Date()) -> Bool {
        guard let expires else { return false }
        return expires <= now.timeIntervalSince1970
    }

    /// Cookie này có được gửi tới `host` không (trùng tên miền hoặc là tên miền con).
    func matches(host: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    init(domain: String, name: String, value: String, expires: Double?) {
        self.domain = domain
        self.name = name
        self.value = value
        self.expires = expires
    }

    /// Từ cookie của WebKit/`HTTPCookieStorage`: bỏ dấu chấm đầu tên miền, viết thường.
    init(httpCookie cookie: HTTPCookie) {
        var host = cookie.domain.lowercased()
        if host.hasPrefix(".") { host.removeFirst() }
        self.init(domain: host, name: cookie.name, value: cookie.value,
                  expires: cookie.expiresDate?.timeIntervalSince1970)
    }

    /// Cookie để đẩy vào `WKHTTPCookieStore` (path `/`).
    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [.domain: domain, .path: "/", .name: name, .value: value]
        if let expires { properties[.expires] = Date(timeIntervalSince1970: expires) }
        return HTTPCookie(properties: properties)
    }
}
