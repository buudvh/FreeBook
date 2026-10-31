import SwiftUI
import UIKit
import WebKit

/// Thao tác của `BypassWebView`: tab đầu / tab mới / Home, nạp địa chỉ gõ tay, tải lại, import truyện, sao chép link.
/// Tách khỏi file gốc để file đó giữ dưới trần 400 dòng.
extension BypassWebView {
    /// Tiện ích đã cài, đọc từ `ExtensionLibraryRepository` (Observation tự theo dõi khi đọc trong `body`), bỏ nguồn
    /// Legado — cùng tập ứng viên với bộ dò link (`ExtensionUrlMatcher.candidates`).
    var activeExtensions: [Extension] {
        ExtensionUrlMatcher.candidates(from: ExtensionLibraryRepository.shared.installed)
    }

    var bookExtensions: [Extension] {
        activeExtensions.filter { !$0.sourceUrl.isEmpty }
    }

    var resolvedUrl: URL? {
        if urlString == "home" { return nil }
        // Link lỗi (`SourceErrorLink.url`) đã là URL tuyệt đối đã kiểm: mở **nguyên văn**. `cleanAndResolveUrl` nhảy tới
        // `http(s)://` cuối cùng trong chuỗi ⇒ URL fetch kiểu `…?url=https://…` sẽ mở nhầm trang và chép nhầm cookie.
        if forcesMobileUserAgent, let direct = URL(string: urlString),
           let scheme = direct.scheme?.lowercased(), scheme == "http" || scheme == "https",
           let directHost = direct.host, !directHost.isEmpty {
            return direct
        }
        let resolvedString = JSExecutor.cleanAndResolveUrl(urlString, host: host)
        return URL(string: resolvedString)
    }

    static func isHomeTab(_ tab: BypassBrowserTab) -> Bool {
        tab.urlString.isEmpty || tab.urlString == "about:blank" || tab.urlString == "Home"
    }

    /// URL trang web (http/https) tab đang hiển thị; Home / trang không phải web ⇒ `nil`.
    func webPageURL(of tab: BypassBrowserTab) -> URL? {
        guard !Self.isHomeTab(tab), let url = URL(string: tab.urlString), BypassBrowserTabStore.isWebURL(url) else {
            return nil
        }
        return url
    }

    /// Tiện ích khớp URL trang (giữ thứ tự `activeExtensions`). Gọi **một lần** mỗi lượt vẽ rồi truyền xuống: thân
    /// view vẽ lại liên tục khi trang đang tải (tiến độ), mỗi lần dò là dựng regex của mọi tiện ích.
    func importMatches(for tab: BypassBrowserTab) -> [ExtensionUrlMatcher.Match] {
        guard !Self.isHomeTab(tab) else { return [] }
        return ExtensionUrlMatcher.matches(for: tab.urlString, in: activeExtensions)
    }

    // MARK: - Tab lifecycle

    func prepareInitialTab() {
        let isFirstMount = store.tabs.isEmpty
        // Đặt trước `prepareFirstTab`: tab đầu phải được tạo với UA điện thoại ngay từ đầu.
        store.forcesMobileUserAgent = forcesMobileUserAgent
        let tab = store.prepareFirstTab(url: resolvedUrl)
        guard isFirstMount else { return }
        // Link lỗi có thể mang token trong query ⇒ tab đầu ẩn danh: không vào Lịch sử. Ẩn danh của trình duyệt này chỉ
        // bỏ ghi lịch sử, cookie vẫn ở kho WebKit mặc định nên chép cookie khi đóng vẫn có tác dụng.
        if forcesMobileUserAgent { tab.isIncognito = true }

        if let pending = tab.consumePendingUrl() {
            tab.load(pending)
        } else {
            loadHome(into: tab)
        }
    }

    func openNewTab() {
        guard let tab = store.openTab() else { return }
        loadHome(into: tab)
    }

    /// Về Home cũng kết thúc ẩn danh của tab (lùi lại trang nguồn thì `BypassBrowserTabStore` bật lại).
    func loadHome(into tab: BypassBrowserTab) {
        tab.isIncognito = false
        tab.webView.load(URLRequest(url: URL(string: "about:blank")!))
        tab.title = "Trang chủ"
        tab.urlString = "about:blank"
    }

    func reload(_ tab: BypassBrowserTab) {
        if Self.isHomeTab(tab) {
            loadHome(into: tab)
        } else if tab.webView.url != nil {
            tab.webView.reload()
        } else if let url = URL(string: tab.urlString) {
            tab.load(url)
        }
    }

    // MARK: - Ô địa chỉ

    /// Chạm tên miền trên thanh dưới: nạp sẵn URL đầy đủ (Home ⇒ rỗng để gõ mới) rồi đổi sang ô nhập.
    func beginEditingUrl(for tab: BypassBrowserTab) {
        inputUrl = Self.isHomeTab(tab) ? "" : tab.urlString
        isEditingUrl = true
    }

    /// Enter ở ô địa chỉ: link thì mở, chữ thường thì tìm Google (`BrowserAddressInputMapper`).
    func loadEnteredUrl(into tab: BypassBrowserTab) {
        let text = inputUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "Home", let url = BrowserAddressInputMapper.url(for: text) else { return }
        tab.load(url)
    }

    // MARK: - Trang này

    func copyLink(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        ToastManager.shared.show(message: "Đã sao chép link", type: .success)
    }

    // MARK: - Import truyện

    /// Mục "Import truyện" của ngăn kéo: 1 nguồn ⇒ import luôn; nhiều nguồn ⇒ mở bảng chọn nguồn của nút Import ở thanh
    /// dưới (nút luôn hiện khi mục này bấm được).
    func importFromMenu(_ matches: [ExtensionUrlMatcher.Match]) {
        guard let first = matches.first else { return }
        if matches.count == 1 {
            importBook(with: first)
        } else {
            showingSourcePicker = true
        }
    }

    func importBook(with match: ExtensionUrlMatcher.Match) {
        guard let tab = store.activeTab else { return }
        onImport?(tab.urlString, match.ext.packageId, match.ext.name)
        dismiss()
    }
}
