import Foundation
import Observation

/// Lớp quan sát cho UI của `BrowserSitePreferenceStore` (màn Cài đặt → Trang đã chỉnh riêng, menu khiên).
///
/// Store là nguồn sự thật (thread-safe, dùng cả ở tầng nền); type này chỉ giữ bản sao `items` trên MainActor để
/// Observation vẽ lại. UI **ghi qua đây** (ghi store rồi `reload()`), không qua NotificationCenter.
@MainActor
@Observable
final class BrowserSitePreferenceList {
    static let shared = BrowserSitePreferenceList()

    private(set) var items: [BrowserSitePreference] = []

    private var store: BrowserSitePreferenceStore { BrowserSitePreferenceStore.shared }

    private init() {
        items = BrowserSitePreferenceStore.shared.all()
    }

    /// Đọc lại từ store (vd mở màn Cài đặt sau khi chỗ khác đã ghi thẳng vào store).
    func reload() {
        let latest = store.all()
        if latest != items { items = latest }
    }

    func setAdBlock(_ value: Bool?, forHost host: String) {
        store.setAdBlock(value, forHost: host)
        reload()
    }

    func setDesktop(_ value: Bool?, forHost host: String) {
        store.setDesktop(value, forHost: host)
        reload()
    }

    func setTranslate(_ value: Bool?, forHost host: String) {
        store.setTranslate(value, forHost: host)
        reload()
    }

    func remove(domain: String) {
        store.remove(domain: domain)
        reload()
    }
}
