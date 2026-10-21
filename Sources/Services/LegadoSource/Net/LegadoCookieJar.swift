import Foundation

/// Kho cookie **theo nguồn** (spec §4.2), dùng chung giữa mọi phiên của nguồn đó trong tiến trình, lưu bền qua
/// `LegadoPersistentStore` (ghi khi phiên kết thúc nếu có thay đổi).
///
/// - `enabledCookieJar = true`: engine tự lưu mọi `Set-Cookie` (mọi chặng chuyển hướng).
/// - Luôn lưu: cookie do JS đặt (`cookie.setCookie`) và cookie đồng bộ từ WebView ẩn; luôn gửi cookie đang có (U19).
/// - Tra theo tên miền: cookie miền `a.com` được gửi cho `a.com` và `x.a.com`.
final class LegadoCookieJar: @unchecked Sendable {
    private static let registryLock = NSLock()
    private static var registry: [String: LegadoCookieJar] = [:]

    private let sourceKey: String
    private let store: LegadoPersistentStore
    private let lock = NSLock()
    private var cookies: [LegadoStoredCookie]
    private var dirty = false

    private init(sourceKey: String, store: LegadoPersistentStore) {
        self.sourceKey = sourceKey
        self.store = store
        self.cookies = store.cookies(sourceKey: sourceKey)
    }

    static func shared(forSourceKey key: String, store: LegadoPersistentStore) -> LegadoCookieJar {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = registry[key] { return existing }
        let jar = LegadoCookieJar(sourceKey: key, store: store)
        registry[key] = jar
        return jar
    }

    // MARK: - Đọc

    /// Giá trị header `Cookie` cho URL (`nil` khi không có cookie nào).
    func cookieHeader(forURL url: String) -> String? {
        let text = cookieString(forURL: url)
        return text.isEmpty ? nil : text
    }

    /// `k=v; k2=v2` của mọi cookie hợp lệ cho tên miền của URL (`cookie.getCookie`).
    func cookieString(forURL url: String) -> String {
        current(forURL: url).map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    /// Giá trị một cookie (`cookie.getKey`); không có ⇒ `""`.
    func value(forURL url: String, name: String) -> String {
        current(forURL: url).last(where: { $0.name == name })?.value ?? ""
    }

    /// Cookie dạng `HTTPCookie` để đẩy sang WebView.
    func httpCookies(forURL url: String) -> [HTTPCookie] {
        current(forURL: url).compactMap { cookie -> HTTPCookie? in
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: cookie.domain, .path: "/", .name: cookie.name, .value: cookie.value
            ]
            if let expires = cookie.expires { properties[.expires] = Date(timeIntervalSince1970: expires) }
            return HTTPCookie(properties: properties)
        }
    }

    /// Cookie đang có cho tên miền của URL (để trao cho trình duyệt hiện cho người dùng).
    func storedCookies(forURL url: String) -> [LegadoStoredCookie] {
        current(forURL: url)
    }

    /// Gộp cookie đọc từ trình duyệt hiện cho người dùng / đăng nhập web (spec §10.2, §10.8) rồi ghi bền ngay.
    func absorbStored(_ received: [LegadoStoredCookie]) {
        guard !received.isEmpty else { return }
        let now = Date()
        lock.lock()
        for cookie in received where !cookie.domain.isEmpty && !cookie.name.isEmpty {
            var normalized = cookie
            normalized.domain = cookie.domain.lowercased()
            if normalized.domain.hasPrefix(".") { normalized.domain.removeFirst() }
            upsert(normalized, expired: normalized.isExpired(at: now))
        }
        lock.unlock()
        flushIfNeeded()
    }

    /// Xoá mọi cookie của nguồn (đăng xuất).
    func removeAll() {
        lock.lock()
        if !cookies.isEmpty {
            cookies.removeAll()
            dirty = true
        }
        lock.unlock()
        flushIfNeeded()
    }

    private func current(forURL url: String) -> [LegadoStoredCookie] {
        guard let host = LegadoURLResolver.host(of: url) else { return [] }
        let now = Date()
        lock.lock()
        defer { lock.unlock() }
        return cookies.filter { $0.matches(host: host) && !$0.isExpired(at: now) }
    }

    // MARK: - Ghi

    /// Cookie từ `Set-Cookie` hoặc từ WebView. Cookie đã hết hạn ⇒ xoá bản đang có.
    func absorb(_ received: [HTTPCookie], defaultHost: String?) {
        guard !received.isEmpty else { return }
        let now = Date()
        lock.lock()
        defer { lock.unlock() }
        for cookie in received {
            var domain = cookie.domain.lowercased()
            if domain.hasPrefix(".") { domain.removeFirst() }
            if domain.isEmpty, let defaultHost { domain = defaultHost }
            guard !domain.isEmpty else { continue }
            let stored = LegadoStoredCookie(domain: domain, name: cookie.name, value: cookie.value,
                                            expires: cookie.expiresDate?.timeIntervalSince1970)
            upsert(stored, expired: stored.isExpired(at: now))
        }
    }

    /// `cookie.setCookie(url, "a=1; b=2")` (gộp) / `cookie.replaceCookie` (thay toàn bộ cookie của tên miền).
    func setCookies(fromString text: String, url: String, replace: Bool) {
        guard let host = LegadoURLResolver.host(of: url) else { return }
        lock.lock()
        defer { lock.unlock() }
        if replace {
            cookies.removeAll { $0.domain == host }
            dirty = true
        }
        for piece in text.components(separatedBy: ";") {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let name = String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            let attribute = name.lowercased()
            guard !name.isEmpty, !["path", "domain", "expires", "max-age", "samesite"].contains(attribute) else { continue }
            upsert(LegadoStoredCookie(domain: host, name: name, value: value, expires: nil), expired: false)
        }
    }

    /// `cookie.removeCookie(url)`: xoá cookie của tên miền (gồm tên miền cha/con khớp).
    func removeCookies(forURL url: String) {
        guard let host = LegadoURLResolver.host(of: url) else { return }
        lock.lock()
        defer { lock.unlock() }
        let before = cookies.count
        cookies.removeAll { $0.matches(host: host) || $0.domain.hasSuffix("." + host) }
        if cookies.count != before { dirty = true }
    }

    /// Ghi xuống kho bền nếu có thay đổi (gọi khi phiên kết thúc).
    func flushIfNeeded() {
        lock.lock()
        guard dirty else {
            lock.unlock()
            return
        }
        dirty = false
        let snapshot = cookies.filter { !$0.isExpired() }
        lock.unlock()
        store.setCookies(snapshot, sourceKey: sourceKey)
    }

    /// Gọi khi đang giữ `lock`.
    private func upsert(_ cookie: LegadoStoredCookie, expired: Bool) {
        cookies.removeAll { $0.domain == cookie.domain && $0.name == cookie.name }
        if !expired { cookies.append(cookie) }
        dirty = true
    }
}
