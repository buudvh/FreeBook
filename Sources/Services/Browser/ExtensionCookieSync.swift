import CryptoKit
import Foundation
import UIKit
import WebKit

/// Đồng bộ cookie WebKit → `URLSession` cho tên miền `source` của tiện ích, ngay trước mỗi lượt chạy script
/// (`JSExecutor.callAsync`). Hợp đồng: `localCookie` và `fetch` dùng chung cookie của nguồn — mà người dùng đăng nhập ở
/// trình duyệt trong app (kho `WKWebsiteDataStore.default()`), còn `fetch` đi `URLSession.shared` (`HTTPCookieStorage.shared`).
///
/// ## Rẻ trên đường nóng
/// Tải truyện chạy một script mỗi chương ⇒ không hỏi WebKit mỗi lượt. Bộ quan sát `WKHTTPCookieStoreObserver` (cài trên
/// main lúc mở app, và lười ở lượt đồng bộ đầu tiên) tăng **thế hệ** mỗi khi kho WebKit đổi; mỗi host nhớ thế hệ đã đồng bộ.
/// Lượt chạy chỉ `await` main khi hai số lệch — host chưa đồng bộ lần nào luôn lệch ⇒ lượt đầu mỗi host sau khi mở app
/// luôn đồng bộ. Thế hệ được đọc **trước** khi đọc kho WebKit: thay đổi rơi vào giữa lượt đọc vẫn làm lượt sau đồng bộ lại.
/// App ở nền (TTS nền) hoặc WebKit không trả lời sau `webKitReadTimeout` ⇒ bỏ lượt, **không** đánh dấu đã đồng bộ.
///
/// ## Chép có so sánh, không ghi đè mù
/// `URLSession` có thể giữ bản mới hơn (máy chủ xoay vòng cookie qua `Set-Cookie` của `fetch`); ghi đè bằng bản cũ của
/// WebKit có thể làm mất đăng nhập. Một cookie WebKit (khoá domain + path + tên, domain so nguyên văn kể cả dấu chấm đầu)
/// chỉ được chép khi `URLSession` chưa có cookie cùng khoá, hoặc giá trị WebKit đã đổi so với lần chép trước. "Lần chép
/// trước" là dấu vân tay SHA-256 của giá trị (không bao giờ lưu giá trị) trong `UserDefaults`, sống qua lần mở app.
/// Chưa có dấu vân tay mà hai bên khác giá trị: lượt trước khi chạy script giữ bản `URLSession` và lấy giá trị WebKit làm
/// mốc; lượt sau khi đăng nhập (`syncNow`) thì WebKit thắng. Cookie WebKit đã hết hạn bị bỏ qua.
///
/// Không log giá trị cookie — chỉ số lượng và host.
final class ExtensionCookieSync: @unchecked Sendable {
    static let shared = ExtensionCookieSync()

    /// Lượt đồng bộ trước khi chạy script chỉ lấy mốc khi thiếu dấu vân tay; lượt sau khi đăng nhập thì chép.
    private enum Mode {
        case beforeRun
        case afterLogin
    }

    private static let fingerprintsDefaultsKey = "extensionCookieSyncFingerprints"
    /// Chờ kho cookie WebKit lâu nhất — tiến trình mạng của WebKit có thể bị treo (app vừa về nền…).
    private static let webKitReadTimeout: TimeInterval = 2
    private static let separator = "\u{1F}"

    private let lock = NSLock()
    private var generation: UInt64 = 0
    /// Host → thế hệ đã đồng bộ. Thiếu khoá ⇒ chưa đồng bộ lần nào.
    private var syncedGenerations: [String: UInt64] = [:]
    /// Chỉ đọc/ghi trên main. Domain cookie (chữ thường, giữ dấu chấm đầu) → (path + US + tên) → SHA-256 hex của giá trị.
    private var fingerprints: [String: [String: String]]?
    /// WebKit không giữ observer ⇒ giữ ở đây. Chỉ đọc/ghi trên main.
    private var observer: CookieStoreObserver?

    // MARK: - Quan sát kho WebKit

    /// Cài bộ quan sát kho cookie WebKit mặc định. Gọi lại vô hại.
    @MainActor
    func startObserving() {
        guard observer == nil else { return }
        let created = CookieStoreObserver()
        observer = created
        WKWebsiteDataStore.default().httpCookieStore.add(created)
    }

    private func markWebKitChanged() {
        lock.lock()
        generation &+= 1
        lock.unlock()
    }

    private func currentGeneration() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    /// Thế hệ hiện tại nếu `host` cần đồng bộ lại; `nil` ⇒ đã đồng bộ ở đúng thế hệ này. (Khoá ở hàm đồng bộ — `NSLock`
    /// không dùng thẳng trong ngữ cảnh `async`.)
    private func staleGeneration(for host: String) -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return syncedGenerations[host] == generation ? nil : generation
    }

    private func markSynced(_ hosts: Set<String>, at syncedGeneration: UInt64) {
        lock.lock()
        for host in hosts {
            syncedGenerations[host] = syncedGeneration
        }
        lock.unlock()
    }

    // MARK: - API

    /// Đường nóng — đầu `JSExecutor.callAsync`, ngoài main. Thế hệ không đổi kể từ lần đồng bộ trước ⇒ trả ngay
    /// (chỉ một lần khoá), không nhảy sang main.
    func syncBeforeRun(sourceURL: URL) async {
        guard let host = Self.host(of: sourceURL), let current = staleGeneration(for: host) else { return }
        await syncFromWebKit(hosts: [host], generation: current, mode: .beforeRun)
    }

    /// Đồng bộ ngay, bỏ qua kiểm thế hệ — sau khi người dùng đóng trang đăng nhập của tiện ích. URL không phải http(s)
    /// bị bỏ qua. Trả số cookie đã chép.
    @MainActor
    @discardableResult
    func syncNow(urlStrings: [String]) async -> Int {
        let hosts = Set(urlStrings.compactMap { raw in
            URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(Self.host(of:))
        })
        guard !hosts.isEmpty else { return 0 }
        return await syncFromWebKit(hosts: hosts, generation: currentGeneration(), mode: .afterLogin)
    }

    /// Ghi dấu vân tay cho cookie vừa được chép **mù** sang `URLSession` (`WebKitCookieBridge`, nút "Mở link lỗi") — để lượt
    /// đồng bộ trước khi chạy script coi đó là "lần chép trước" và không ghi đè bản `Set-Cookie` mới hơn về sau.
    @MainActor
    func recordCopied(_ cookies: [HTTPCookie]) {
        guard !cookies.isEmpty else { return }
        let original = loadedFingerprints()
        var prints = original
        for cookie in cookies {
            prints[cookie.domain.lowercased(), default: [:]][Self.slot(of: cookie)] = Self.fingerprint(cookie.value)
        }
        saveFingerprints(prints, ifChangedFrom: original)
    }

    // MARK: - Đồng bộ

    @MainActor
    @discardableResult
    private func syncFromWebKit(hosts: Set<String>, generation: UInt64, mode: Mode) async -> Int {
        startObserving()
        let target = hosts.sorted().joined(separator: ", ")
        guard UIApplication.shared.applicationState != .background else { return 0 }
        guard let webKitCookies = await Self.readWebKitCookies() else {
            AppLogger.shared.log("❌ [ExtensionCookieSync] Kho cookie WebKit không trả lời sau \(Int(Self.webKitReadTimeout)) s — bỏ lượt đồng bộ \(target)")
            return 0
        }

        let storage = HTTPCookieStorage.shared
        var jar: [String: HTTPCookie] = [:]
        for cookie in storage.cookies ?? [] {
            jar[cookie.domain.lowercased() + Self.separator + Self.slot(of: cookie)] = cookie
        }
        let original = loadedFingerprints()
        var prints = original
        let now = Date()
        var copied = 0

        for host in hosts {
            let matching = webKitCookies.filter { cookie in
                WebKitCookieBridge.appliesTo(host, cookieDomain: cookie.domain) && (cookie.expiresDate.map { $0 > now } ?? true)
            }
            var liveSlots: [String: Set<String>] = [:]
            for cookie in matching {
                let domain = cookie.domain.lowercased()
                let slot = Self.slot(of: cookie)
                let hash = Self.fingerprint(cookie.value)
                liveSlots[domain, default: []].insert(slot)
                if Self.shouldCopy(cookie, jarCookie: jar[domain + Self.separator + slot],
                                   recorded: prints[domain]?[slot], hash: hash, mode: mode) {
                    storage.setCookie(cookie)
                    copied += 1
                }
                prints[domain, default: [:]][slot] = hash
            }
            // Cookie đã biến khỏi WebKit (đăng xuất, hết hạn) ⇒ bỏ dấu vân tay để kho không phình mãi.
            for domain in prints.keys where WebKitCookieBridge.appliesTo(host, cookieDomain: domain) {
                let live = liveSlots[domain] ?? []
                let kept = (prints[domain] ?? [:]).filter { live.contains($0.key) }
                prints[domain] = kept.isEmpty ? nil : kept
            }
        }
        saveFingerprints(prints, ifChangedFrom: original)
        markSynced(hosts, at: generation)
        if copied > 0 || mode == .afterLogin {
            AppLogger.shared.log("[ExtensionCookieSync] Đã chép \(copied) cookie WebKit sang fetch cho \(target)")
        }
        return copied
    }

    /// Luật chép của một cookie WebKit — xem chú thích của type.
    private static func shouldCopy(_ cookie: HTTPCookie, jarCookie: HTTPCookie?, recorded: String?,
                                   hash: String, mode: Mode) -> Bool {
        guard let jarCookie else { return true }
        if jarCookie.value == cookie.value { return false }
        if let recorded { return recorded != hash }
        return mode == .afterLogin
    }

    /// Đọc mọi cookie của kho WebKit mặc định, chờ tối đa `webKitReadTimeout`; quá hạn ⇒ `nil`.
    @MainActor
    private static func readWebKitCookies() async -> [HTTPCookie]? {
        let once = OnceFlag()
        let timeoutNanoseconds = UInt64(Self.webKitReadTimeout * 1_000_000_000)
        return await withCheckedContinuation { (continuation: CheckedContinuation<[HTTPCookie]?, Never>) in
            Task { @MainActor in
                let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
                if once.claim() { continuation.resume(returning: cookies) }
            }
            Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                if once.claim() { continuation.resume(returning: nil) }
            }
        }
    }

    // MARK: - Dấu vân tay

    @MainActor
    private func loadedFingerprints() -> [String: [String: String]] {
        if let fingerprints { return fingerprints }
        let stored = UserDefaults.standard.dictionary(forKey: Self.fingerprintsDefaultsKey) as? [String: [String: String]] ?? [:]
        fingerprints = stored
        return stored
    }

    @MainActor
    private func saveFingerprints(_ prints: [String: [String: String]], ifChangedFrom original: [String: [String: String]]) {
        guard prints != original else { return }
        fingerprints = prints
        UserDefaults.standard.set(prints, forKey: Self.fingerprintsDefaultsKey)
    }

    private static func slot(of cookie: HTTPCookie) -> String {
        cookie.path + separator + cookie.name
    }

    private static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Host (chữ thường) của URL http(s); khác ⇒ `nil`.
    static func host(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return host
    }

    // MARK: - Kiểu phụ

    /// WebKit gọi trên main mỗi khi kho cookie mặc định đổi (trang đặt cookie, đăng nhập, đăng xuất…).
    private final class CookieStoreObserver: NSObject, WKHTTPCookieStoreObserver {
        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            ExtensionCookieSync.shared.markWebKitChanged()
        }
    }

    /// Cờ "chỉ một lần" cho cuộc đua giữa lượt đọc WebKit và hạn chờ.
    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}
