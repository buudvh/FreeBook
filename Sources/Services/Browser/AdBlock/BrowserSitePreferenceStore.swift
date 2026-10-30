import Foundation
import os

/// Chỉnh riêng theo **tên miền** của trình duyệt người dùng (menu khiên): chặn quảng cáo, xem bản máy tính, tự dịch
/// QT (`translate`, đọc bởi `BrowserTranslatePolicy`).
/// Chủ sở hữu **duy nhất** của `applicationSupportDirectory/adblock/site_preferences.json` (mảng
/// `BrowserSitePreference` sắp theo `domain`).
///
/// Thread-safe: được `WebContentPolicy` gọi từ delegate điều hướng (main) lẫn UI. Chỉ giữ lock trong lúc đọc/ghi
/// dictionary RAM; file nạp lười lần đầu (đọc ngoài lock) và ghi gom trên queue nền.
///
/// Chuẩn hoá tên miền: lowercase, bỏ dấu chấm cuối, bỏ tiền tố `www.`. Tra cứu: khớp chính xác rồi lần lượt
/// **tên miền cha** (`a.b.com` → `b.com`), dừng khi chỉ còn 1 nhãn; địa chỉ IP chỉ khớp chính xác. Không dùng
/// Public Suffix List (chấp nhận ở đợt 1: `blogspot.com` gộp mọi blog con).
///
/// Mỗi trường lấy giá trị **gần nhất khác `nil`** dọc chuỗi tra: chỉnh `m.b.com` chỉ đè đúng trường đã chỉnh,
/// trường còn lại vẫn thừa hưởng từ `b.com`.
final class BrowserSitePreferenceStore: @unchecked Sendable {
    static let shared = BrowserSitePreferenceStore()

    private struct State: Sendable {
        var isLoaded = false
        var items: [String: BrowserSitePreference] = [:]
        var isWriteScheduled = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let writeQueue = DispatchQueue(label: "FreeBook.BrowserSitePreferenceStore", qos: .utility)

    private init() {}

    // MARK: - Chuẩn hoá

    /// `nil` khi host rỗng (trang Home, `about:blank`…).
    static func normalizedDomain(for host: String?) -> String? {
        guard var domain = host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !domain.isEmpty else {
            return nil
        }
        while domain.hasSuffix(".") { domain.removeLast() }
        if domain.hasPrefix("www.") { domain.removeFirst(4) }
        return domain.isEmpty ? nil : domain
    }

    /// `[domain, cha, ông…]` — chỉ các tên miền còn ≥ 2 nhãn. IP (v4/v6) chỉ có chính nó.
    private static func lookupChain(for domain: String) -> [String] {
        var labels = domain.split(separator: ".", omittingEmptySubsequences: true)
        let isIPv4 = !labels.isEmpty && labels.allSatisfy { $0.allSatisfy(\.isNumber) }
        if domain.contains(":") || isIPv4 { return [domain] }
        var chain = [domain]
        while labels.count > 2 {
            labels.removeFirst()
            chain.append(labels.joined(separator: "."))
        }
        return chain
    }

    // MARK: - Đọc

    /// Chỉnh riêng có hiệu lực cho `host`; `nil` khi không tên miền nào trong chuỗi tra có bản ghi.
    /// `domain` của kết quả = tên miền **cụ thể nhất** có bản ghi.
    func preference(forHost host: String?) -> BrowserSitePreference? {
        guard let domain = Self.normalizedDomain(for: host) else { return nil }
        let chain = Self.lookupChain(for: domain)
        ensureLoaded()
        return state.withLock { (s) -> BrowserSitePreference? in
            var matched: String?
            var adBlock: Bool?
            var desktop: Bool?
            var translate: Bool?
            for candidate in chain {
                guard let item = s.items[candidate] else { continue }
                if matched == nil { matched = candidate }
                if adBlock == nil { adBlock = item.adBlock }
                if desktop == nil { desktop = item.desktop }
                if translate == nil { translate = item.translate }
                if adBlock != nil, desktop != nil, translate != nil { break }
            }
            guard let matched else { return nil }
            return BrowserSitePreference(domain: matched, adBlock: adBlock, desktop: desktop, translate: translate)
        }
    }

    /// Mọi bản ghi, sắp theo `domain` (màn Cài đặt → Trang đã chỉnh riêng).
    func all() -> [BrowserSitePreference] {
        ensureLoaded()
        return state.withLock { s in Self.sorted(s.items) }
    }

    // MARK: - Ghi

    /// Ghi vào đúng tên miền chuẩn hoá của `host` (không ghi lên tên miền cha). `nil` = về theo cài đặt chung.
    func setAdBlock(_ value: Bool?, forHost host: String) {
        mutate(host: host) { $0.adBlock = value }
    }

    func setDesktop(_ value: Bool?, forHost host: String) {
        mutate(host: host) { $0.desktop = value }
    }

    /// Nhớ tự dịch QT theo tên miền (công tắc trong menu khiên). `nil` = về theo tiện ích khớp URL rồi tắt.
    func setTranslate(_ value: Bool?, forHost host: String) {
        mutate(host: host) { $0.translate = value }
    }

    /// Xoá hẳn bản ghi (vuốt xoá trong Cài đặt) — tên miền về theo mặc định.
    func remove(domain: String) {
        guard let key = Self.normalizedDomain(for: domain) else { return }
        ensureLoaded()
        let changed = state.withLock { (s) -> Bool in
            s.items.removeValue(forKey: key) != nil
        }
        if changed { scheduleWrite() }
    }

    private func mutate(host: String, _ body: @escaping @Sendable (inout BrowserSitePreference) -> Void) {
        guard let key = Self.normalizedDomain(for: host) else { return }
        ensureLoaded()
        let changed = state.withLock { (s) -> Bool in
            let before = s.items[key]
            var item = before ?? BrowserSitePreference(domain: key, adBlock: nil, desktop: nil, translate: nil)
            body(&item)
            // Mọi trường nil ⇒ xoá bản ghi: dữ liệu khớp đúng "theo mặc định".
            let after: BrowserSitePreference? = item.isEmpty ? nil : item
            guard after != before else { return false }
            s.items[key] = after
            return true
        }
        if changed { scheduleWrite() }
    }

    // MARK: - File

    /// Nạp file lần đầu. Đọc **ngoài** lock; hai thread cùng nạp thì bản nạp sau bị bỏ.
    private func ensureLoaded() {
        if state.withLock({ $0.isLoaded }) { return }
        let loaded = Self.readFile()
        state.withLock { s in
            guard !s.isLoaded else { return }
            s.items = loaded
            s.isLoaded = true
        }
    }

    private static func readFile() -> [String: BrowserSitePreference] {
        let url = AdBlockPaths.sitePreferencesFile
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let data = try Data(contentsOf: url)
            let list = try JSONDecoder().decode([BrowserSitePreference].self, from: data)
            var items: [String: BrowserSitePreference] = [:]
            for item in list where !item.isEmpty {
                guard let key = normalizedDomain(for: item.domain) else { continue }
                items[key] = BrowserSitePreference(
                    domain: key, adBlock: item.adBlock, desktop: item.desktop, translate: item.translate
                )
            }
            return items
        } catch {
            // Hỏng file ⇒ coi như chưa chỉnh trang nào (mọi trang theo mặc định); lần ghi sau thay file mới.
            AppLogger.shared.log("❌ 🛡️ [AdBlock] Không đọc được site_preferences.json: \(error.localizedDescription)")
            return [:]
        }
    }

    /// Gom ghi: một lượt ghi đang xếp hàng sẽ lấy trạng thái **mới nhất** lúc chạy.
    private func scheduleWrite() {
        let shouldSchedule = state.withLock { (s) -> Bool in
            guard !s.isWriteScheduled else { return false }
            s.isWriteScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        writeQueue.async { [weak self] in
            self?.writeNow()
        }
    }

    /// Chỉ chạy trên `writeQueue`.
    private func writeNow() {
        let list = state.withLock { (s) -> [BrowserSitePreference] in
            s.isWriteScheduled = false
            return Self.sorted(s.items)
        }
        guard AdBlockPaths.ensureDirectory(AdBlockPaths.rootDirectory) else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(list)
            try data.write(to: AdBlockPaths.sitePreferencesFile, options: .atomic)
        } catch {
            AppLogger.shared.log("❌ 🛡️ [AdBlock] Không ghi được site_preferences.json: \(error.localizedDescription)")
        }
    }

    private static func sorted(_ items: [String: BrowserSitePreference]) -> [BrowserSitePreference] {
        items.values.sorted { $0.domain < $1.domain }
    }
}
