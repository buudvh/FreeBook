import Foundation
import WebKit

/// Chép cookie từ kho WebKit mặc định (`WKWebsiteDataStore.default()` — trình duyệt bypass, browser ẩn của tiện ích)
/// sang `HTTPCookieStorage.shared` (kho của `URLSession.shared`, đường `fetch` của `JSExecutor`). Hai kho **không** tự
/// thông nhau: qua Cloudflare/đăng nhập trong trình duyệt xong, `fetch` vẫn không có cookie nếu không chép.
///
/// Dùng sau khi người dùng đóng trình duyệt mở từ nút "Mở link lỗi" (`.errorLinkBrowser`), ngay trước khi thử lại.
///
/// Giới hạn đã biết:
/// - Chép cookie chưa chắc đủ để `URLSession` qua Cloudflare (dấu vân tay TLS/HTTP2 khác Safari); lần thử lại vẫn 403
///   thì fallback browser ẩn của `fetch` dùng thẳng kho WebKit nên vẫn còn cơ hội.
/// - Tiện ích đặt `http_should_handle_cookies = false` thì `fetch` không gửi cookie trong `HTTPCookieStorage`.
/// - Nguồn Legado không dùng `HTTPCookieStorage` (kho cookie riêng theo nguồn) ⇒ truyền `sourcePackageId` để gộp thêm
///   vào kho đó (`LegadoLoginService.importErrorLinkCookies`).
///
/// Không log giá trị cookie — chỉ số lượng và host.
enum WebKitCookieBridge {
    /// Chép mọi cookie WebKit áp được cho `host` (cookie của chính host hoặc của tên miền cha — domain có/không dấu
    /// chấm đầu) sang `HTTPCookieStorage.shared`. Cookie trùng tên/domain/path bị ghi đè bằng bản WebKit, và được ghi dấu
    /// vân tay (`ExtensionCookieSync.recordCopied`) để lượt đồng bộ trước khi chạy script không ghi đè bản mới hơn về sau.
    /// `sourcePackageId` là nguồn Legado ⇒ cùng các cookie đó được gộp vào kho cookie của nguồn (tiện ích JS ⇒ bỏ qua).
    /// Trả số cookie đã chép; host rỗng ⇒ 0.
    @MainActor
    @discardableResult
    static func copyCookies(toURLSessionFor host: String, sourcePackageId: String? = nil) async -> Int {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return 0 }
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let matching = cookies.filter { appliesTo(target, cookieDomain: $0.domain) }
        for cookie in matching {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        ExtensionCookieSync.shared.recordCopied(matching)
        AppLogger.shared.log("[WebKitCookieBridge] Đã chép \(matching.count) cookie cho \(target)")
        if let sourcePackageId, !sourcePackageId.isEmpty, !matching.isEmpty {
            // Hàm không gắn actor ⇒ tra nguồn (có thể đọc `source.json`) chạy ngoài main.
            await LegadoLoginService.importErrorLinkCookies(matching, packageId: sourcePackageId)
        }
        return matching.count
    }

    /// Xoá khỏi kho WebKit mặc định mọi cookie gắn với `hosts`: cookie áp được cho host (của chính host hoặc tên miền cha)
    /// và cookie của tên miền con của host. Không đụng tên miền khác (Google, GitHub… đã ghé lúc đăng nhập OAuth).
    /// Dùng khi đăng xuất nguồn Legado — trình duyệt Legado dùng chung kho này. Trả số cookie đã xoá.
    @MainActor
    @discardableResult
    static func removeCookies(forHosts hosts: Set<String>) async -> Int {
        let targets = Set(hosts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        guard !targets.isEmpty else { return 0 }
        let store = WKWebsiteDataStore.default().httpCookieStore
        let matching = await store.allCookies().filter { cookie in
            var domain = cookie.domain.lowercased()
            while domain.hasPrefix(".") { domain.removeFirst() }
            return targets.contains { appliesTo($0, cookieDomain: cookie.domain) || domain.hasSuffix("." + $0) }
        }
        for cookie in matching {
            await store.deleteCookie(cookie)
        }
        AppLogger.shared.log("[WebKitCookieBridge] Đã xoá \(matching.count) cookie của \(targets.sorted().joined(separator: ", "))")
        return matching.count
    }

    /// `host` trùng domain cookie hoặc là tên miền con của nó (`a.b.com` nhận cookie `.b.com` / `b.com`).
    /// Dùng chung với `ExtensionCookieSync`.
    static func appliesTo(_ host: String, cookieDomain: String) -> Bool {
        var domain = cookieDomain.lowercased()
        while domain.hasPrefix(".") { domain.removeFirst() }
        guard !domain.isEmpty else { return false }
        return host == domain || host.hasSuffix("." + domain)
    }
}
