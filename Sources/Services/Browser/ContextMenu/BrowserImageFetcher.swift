import Foundation
import UIKit

/// Tải ảnh cho menu nhấn giữ của trình duyệt (Lưu ảnh / Sao chép ảnh).
///
/// Gửi kèm `Referer` = URL trang (nhiều trang chặn ảnh hotlink theo header này), User-Agent của trang và cookie kho
/// WebKit áp được cho URL ảnh (kho WebKit **không** thông với `HTTPCookieStorage.shared`). Dùng phiên `ephemeral`
/// riêng và tắt `httpShouldHandleCookies` ⇒ không ghi gì vào kho cookie chung của app.
///
/// Hỗ trợ `http(s)` và `data:`; `blob:` / scheme khác ⇒ `FetchError.unsupportedScheme`. Không log URL ảnh.
enum BrowserImageFetcher {
    enum FetchError: Error {
        case unsupportedScheme
        case badStatus(Int)
        case tooLarge
        case notAnImage
    }

    /// Trần dung lượng ảnh tải về.
    static let maxBytes = 40 * 1024 * 1024

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    static func isSupported(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https" || scheme == "data"
    }

    /// Tải và giải mã ảnh. Hàm không gắn actor — chạy ngoài main.
    static func image(
        from url: URL,
        referer: URL?,
        userAgent: String?,
        cookies: [HTTPCookie]
    ) async throws -> UIImage {
        guard isSupported(url) else { throw FetchError.unsupportedScheme }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        if url.scheme?.lowercased() != "data" {
            request.httpShouldHandleCookies = false
            request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            if let referer, let scheme = referer.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
            }
            if let userAgent, !userAgent.isEmpty {
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            }
            let matching = cookies.filter { applies($0, to: url) }
            if !matching.isEmpty {
                for (field, value) in HTTPCookie.requestHeaderFields(with: matching) {
                    request.setValue(value, forHTTPHeaderField: field)
                }
            }
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.badStatus(http.statusCode)
        }
        guard data.count <= maxBytes else { throw FetchError.tooLarge }
        guard let image = UIImage(data: data) else { throw FetchError.notAnImage }
        return image
    }

    /// Cookie áp được cho URL: tên miền (có/không dấu chấm đầu, gồm tên miền cha), đường dẫn, `Secure` chỉ với https,
    /// chưa hết hạn.
    private static func applies(_ cookie: HTTPCookie, to url: URL) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        var domain = cookie.domain.lowercased()
        while domain.hasPrefix(".") { domain.removeFirst() }
        guard !domain.isEmpty, host == domain || host.hasSuffix("." + domain) else { return false }
        if cookie.isSecure, url.scheme?.lowercased() != "https" { return false }
        if let expires = cookie.expiresDate, expires < Date() { return false }
        let path = url.path.isEmpty ? "/" : url.path
        let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
        return path.hasPrefix(cookiePath)
    }
}
