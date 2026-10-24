import Foundation

/// Dò trang web thuộc **nguồn đã cài** nào theo tên miền, cho trình duyệt người dùng: tự ẩn danh khi vào trang của
/// nguồn đang tắt "Lưu lịch sử đọc/xem" (`ExtensionHistoryPolicy`), và ẩn lịch sử duyệt của nguồn NSFW khi công tắc
/// NSFW toàn app tắt.
///
/// So **một chiều**: trang khớp nguồn khi host của trang trùng tên miền `sourceUrl` của nguồn hoặc là tên miền con
/// của nó (`m.abc.com` khớp nguồn `abc.com`, ngược lại thì không) — so hai chiều thì một nguồn ở `xyz.blogspot.com`
/// kéo cả `blogspot.com` vào. Hai phía đều bỏ `www.` (`BrowserSitePreferenceStore.normalizedDomain`).
///
/// Gồm cả nguồn Legado (hàng nghìn mục; nguồn NSFW mặc định không lưu lịch sử). Đọc bảng chụp có lock của kho tiện
/// ích nên gọi được từ thread bất kỳ.
struct BrowserSourceSiteIndex {
    private let sourcesByDomain: [String: [Extension]]

    /// Mỗi nguồn phân tích URL một lần — dùng khi tra nhiều host (danh sách lịch sử duyệt).
    init(extensions: [Extension] = ExtensionLibraryRepository.installedSnapshot()) {
        var map: [String: [Extension]] = [:]
        for ext in extensions {
            guard let domain = Self.domain(ofSourceUrl: ext.sourceUrl) else { continue }
            map[domain, default: []].append(ext)
        }
        sourcesByDomain = map
    }

    /// Chỉ dựng cho **một** host (mỗi điều hướng): lọc thô bằng chuỗi con của tên miền gốc trước, nên chỉ phân tích
    /// URL của vài nguồn có khả năng khớp thay vì cả nghìn.
    init(host: String?) {
        guard let base = Self.lookupChain(for: host).last else {
            self.init(extensions: [])
            return
        }
        self.init(extensions: ExtensionLibraryRepository.installedSnapshot().filter {
            $0.sourceUrl.range(of: base, options: .caseInsensitive) != nil
        })
    }

    func sources(forHost host: String?) -> [Extension] {
        Self.lookupChain(for: host).flatMap { sourcesByDomain[$0] ?? [] }
    }

    /// Trang thuộc nguồn đang tắt "Lưu lịch sử đọc/xem" ⇒ trình duyệt ẩn danh.
    func isPrivate(host: String?) -> Bool {
        sources(forHost: host).contains { !ExtensionHistoryPolicy.recordsHistory(for: $0) }
    }

    func isNsfw(host: String?) -> Bool {
        sources(forHost: host).contains { ExtensionNsfwCache.shared.isNsfw($0) }
    }

    static func isPrivate(url: URL) -> Bool {
        BrowserSourceSiteIndex(host: url.host).isPrivate(host: url.host)
    }

    /// Bỏ mục lịch sử duyệt thuộc trang của nguồn NSFW — dựng chỉ mục một lần cho cả danh sách.
    static func excludingNsfwSites(_ items: [BrowserHistoryStore.Item]) -> [BrowserHistoryStore.Item] {
        let index = BrowserSourceSiteIndex()
        return items.filter { !index.isNsfw(host: URL(string: $0.urlString)?.host) }
    }

    private static func domain(ofSourceUrl raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return BrowserSitePreferenceStore.normalizedDomain(for: URL(string: trimmed)?.host)
    }

    /// `[domain, cha, ông…]` dừng ở tên miền còn 2 nhãn; IP chỉ có chính nó (như `BrowserSitePreferenceStore`).
    private static func lookupChain(for host: String?) -> [String] {
        guard let domain = BrowserSitePreferenceStore.normalizedDomain(for: host) else { return [] }
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
}
