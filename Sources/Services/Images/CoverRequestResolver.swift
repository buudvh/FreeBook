import Foundation

/// Quy tắc dùng chung cho mọi lượt tải ảnh bìa / ảnh mục từ mạng (`CoverImageLoader`, `ImageCacheManager`):
///
/// - **URL hiển thị** (`displayURL`): bìa cũ đã lưu dạng tương đối hoặc `//cdn…` được ghép lúc hiển thị bằng
///   `ExtensionURLFormatter.resolveAssetURL` với host item (khác rỗng) → `source` của tiện ích. Không backfill dữ liệu.
/// - **`Referer`** (`referer`): origin + "/" của host item (khác rỗng) → `source` — nhiều CDN ảnh chặn hotlink, trả
///   403 khi thiếu (ca thật: CDN bìa của truyenqq chỉ trả 200 khi có `Referer: https://truyenqqko.com/`).
/// - **User-Agent** iPhone Safari, giống `fetch` của script (`JSExecutor`).
///
/// Thuần, không trạng thái; tra `source` qua bảng chụp có lock của kho tiện ích nên gọi được từ thread bất kỳ.
enum CoverRequestResolver {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// Host gốc của item: host item (khác rỗng) → `source` của tiện ích theo `packageId`.
    static func baseHost(itemHost: String?, packageId: String?) -> String? {
        if let host = ExtensionHostResolver.nonEmpty(itemHost) { return host }
        guard let packageId = ExtensionHostResolver.nonEmpty(packageId) else { return nil }
        return ExtensionHostResolver.sourceUrl(packageId: packageId)
    }

    /// `Referer` cho ảnh của một item (dạng origin + "/"); `nil` khi không suy ra được host http(s).
    static func referer(itemHost: String?, packageId: String?) -> String? {
        origin(baseHost(itemHost: itemHost, packageId: packageId))
    }

    /// Chuẩn hoá host / `source` / URL bất kỳ về `scheme://host[:port]/`:
    /// `https://a.com/x/y` ⇒ `https://a.com/`, `//a.com` ⇒ `https://a.com/`, `a.com` ⇒ `https://a.com/`.
    /// Không phải http(s) hoặc không parse được ⇒ `nil` (không gửi header).
    static func origin(_ raw: String?) -> String? {
        guard var value = ExtensionHostResolver.nonEmpty(raw) else { return nil }
        if value.hasPrefix("//") {
            value = "https:" + value
        } else if !value.contains("://") {
            value = "https://" + value
        }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let hostName = components.host, !hostName.isEmpty else { return nil }
        var result = "\(scheme)://\(hostName)"
        if let port = components.port {
            result += ":\(port)"
        }
        return result + "/"
    }

    /// URL ảnh để tải: tuyệt đối (`http(s)`/`data:`) giữ nguyên; tương đối hoặc `//` ⇒ `resolveAssetURL` với
    /// host item → `source`. Chỉ tra `source` khi thật sự cần ghép.
    static func displayURL(_ raw: String, itemHost: String?, packageId: String?) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if isAbsolute(trimmed) { return trimmed }
        return ExtensionURLFormatter.resolveAssetURL(trimmed, host: baseHost(itemHost: itemHost, packageId: packageId))
    }

    /// `http(s)://…` hoặc `data:` — không cần ghép host.
    static func isAbsolute(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("data:")
    }

    /// Request ảnh kèm UA iPhone Safari và `Referer` (đã chuẩn hoá về origin + "/"; rỗng/không hợp lệ ⇒ không gửi).
    static func request(for url: URL, referer: String?, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let referer = origin(referer) {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        return request
    }
}
