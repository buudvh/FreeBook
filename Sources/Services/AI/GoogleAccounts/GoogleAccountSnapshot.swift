import Foundation

/// Ảnh chụp phiên đăng nhập Google của **một** profile Chế độ AI (1.3.614).
///
/// iOS không có `WKWebsiteDataStore(forIdentifier:)` (chỉ macOS) nên app chỉ có một kho cookie Google tại một thời điểm.
/// Muốn nhiều tài khoản thì phải tự lưu/khôi phục: mỗi profile Chế độ AI giữ một snapshot trong Keychain
/// (`GoogleAccountSnapshotStore`), `GoogleSessionSwitcher` tráo vào `WKWebsiteDataStore.default()` trước mỗi lượt.
///
/// Chỉ giữ cookie domain `*.google.com` — Chế độ AI và Gemini Web đều nằm trong domain đó. `sessionFingerprint` băm
/// cookie phiên `__Secure-1PSID` để biết kho đang chứa tài khoản nào mà không cần đọc email từ trang Google.
struct GoogleAccountSnapshot: Codable, Sendable, Equatable {
    /// Cookie đã tách khỏi `HTTPCookie` để `Codable` được. Thiếu `sameSite` là chấp nhận được: mọi điều hướng của app
    /// đều trong `google.com` nên không phải request cross-site.
    struct Cookie: Codable, Sendable, Equatable {
        var name: String
        var value: String
        var domain: String
        var path: String
        var expiresAt: Date?
        var isSecure: Bool
        var isHTTPOnly: Bool
    }

    var profileId: String
    var cookies: [Cookie]
    var savedAt: Date
    var sessionFingerprint: String

    /// Cookie mang phiên đăng nhập Google — có nó là đã đăng nhập (`GeminiWebSessionController+Account.isSignedIn`).
    static let sessionCookieName = "__Secure-1PSID"

    /// `nil` khi kho không có cookie phiên (chưa đăng nhập) — không lưu snapshot rỗng.
    init?(profileId: String, cookies: [HTTPCookie], savedAt: Date = Date()) {
        let google = Self.googleCookies(of: cookies)
        guard let fingerprint = Self.fingerprint(of: google) else { return nil }
        self.profileId = profileId
        self.savedAt = savedAt
        self.sessionFingerprint = fingerprint
        self.cookies = google.map {
            Cookie(
                name: $0.name,
                value: $0.value,
                domain: $0.domain,
                path: $0.path,
                expiresAt: $0.expiresDate,
                isSecure: $0.isSecure,
                isHTTPOnly: $0.isHTTPOnly
            )
        }
    }

    var isEmpty: Bool {
        cookies.isEmpty || sessionFingerprint.isEmpty
    }

    /// Cookie để nạp lại vào `WKHTTPCookieStore`. Cookie hỏng (`HTTPCookie(properties:)` trả `nil`) bị bỏ qua.
    var httpCookies: [HTTPCookie] {
        cookies.compactMap { cookie in
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name,
                .value: cookie.value,
                .domain: cookie.domain,
                .path: cookie.path,
                .secure: cookie.isSecure ? "TRUE" : "FALSE"
            ]
            if let expiresAt = cookie.expiresAt {
                properties[.expires] = expiresAt
            }
            if cookie.isHTTPOnly {
                properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
            }
            return HTTPCookie(properties: properties)
        }
    }

    static func googleCookies(of cookies: [HTTPCookie]) -> [HTTPCookie] {
        cookies.filter { $0.domain.hasSuffix("google.com") }
    }

    /// FNV-1a 64 bit trên giá trị cookie phiên — chỉ để **so khớp** tài khoản, không phải bảo mật.
    static func fingerprint(of cookies: [HTTPCookie]) -> String? {
        guard let session = cookies.first(where: { $0.name == sessionCookieName }), !session.value.isEmpty else {
            return nil
        }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in session.value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
