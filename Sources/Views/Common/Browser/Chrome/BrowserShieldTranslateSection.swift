import SwiftUI

/// Hàng "Tự dịch QT" trong bảng khiên (mockup 2026-10-30, màn "Mới 3"): nhớ tự dịch theo tên miền.
///
/// - Công tắc hiện **luật nhớ** (`BrowserTranslatePolicy.resolve(urlString:).isEnabled`), không phải trạng thái dịch
///   của tab (cái đó còn tính nút dịch bấm tay, không ghi nhớ).
/// - Dòng phụ theo nguồn quyết định: "Đang theo tiện ích <tên>" / "Bật cho <tên miền>" / "Tắt cho <tên miền>" /
///   "Chưa bật".
/// - Đổi công tắc ⇒ luôn ghi giá trị **tường minh** cho tên miền của tab (như mockup: bấm là thành "Bật/Tắt cho …" và
///   hiện dòng "Dùng cấu hình tiện ích"), rồi `reapplyTranslationPolicy` để trang dịch/khôi phục ngay, không nạp lại.
/// - "Dùng cấu hình tiện ích" (chỉ khi đang có chỉnh riêng) ⇒ ghi `nil`.
///
/// Ghi qua `BrowserSitePreferenceList` (như chặn QC / bản máy tính) để màn Cài đặt Trình duyệt đồng bộ. Đọc
/// `BrowserSitePreferenceList.shared.items` trong `body` chỉ để SwiftUI vẽ lại khi bản ghi đổi — store gốc không quan
/// sát được.
struct BrowserShieldTranslateSection: View {
    @ObservedObject var store: BypassBrowserTabStore
    @ObservedObject var tab: BypassBrowserTab
    /// Host trang tab đang hiển thị (`BypassBrowserShieldButton.pageHost(of:)`) — host **ghi** chỉnh riêng.
    let host: String

    var body: some View {
        let _ = BrowserSitePreferenceList.shared.items
        let resolution = BrowserTranslatePolicy.resolve(urlString: tab.urlString)

        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: binding(resolution.isEnabled)) {
                HStack(spacing: 10) {
                    AppGlyph.translate.image(size: 18)
                        .foregroundColor(.white)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tự dịch QT")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text(subtitle(for: resolution))
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .tint(.green)

            if resolution.siteOverride != nil {
                Button {
                    resetToExtensionRule()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 24)
                        Text("Dùng cấu hình tiện ích")
                            .font(.system(size: 13.5, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(.white)
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var domainText: String {
        BrowserSitePreferenceStore.normalizedDomain(for: host) ?? host
    }

    private func subtitle(for resolution: BrowserTranslateResolution) -> String {
        switch resolution.source {
        case .site:
            return resolution.isEnabled ? "Bật cho \(domainText)" : "Tắt cho \(domainText)"
        case .`extension`(let name):
            return "Đang theo tiện ích \(name)"
        case .none:
            return "Chưa bật"
        }
    }

    /// Như `ExtensionConfigView.savesHistoryBinding`: chụp giá trị trong lượt vẽ, ghi qua `MainActor.assumeIsolated`.
    private func binding(_ isOn: Bool) -> Binding<Bool> {
        Binding(
            get: { isOn },
            set: { value in
                guard value != isOn else { return }
                MainActor.assumeIsolated { remember(value) }
            }
        )
    }

    @MainActor
    private func remember(_ value: Bool) {
        BrowserSitePreferenceList.shared.setTranslate(value, forHost: host)
        AppLogger.shared.log("🌐 [BypassBrowser] \(value ? "Bật" : "Tắt") tự dịch QT (nhớ theo tên miền)")
        store.reapplyTranslationPolicy(for: tab)
    }

    /// Ghi `nil` cho host của tab. Tra cứu gộp cả tên miền cha (`BrowserSitePreferenceStore.preference(forHost:)`) nên
    /// bản ghi dịch của tên miền cha cũng bị xoá — nếu không, bấm xong trang vẫn theo chỉnh riêng thừa hưởng và nút như
    /// không có tác dụng. Chỉ xoá trường dịch, chặn QC / bản máy tính của tên miền cha giữ nguyên.
    private func resetToExtensionRule() {
        MainActor.assumeIsolated {
            let list = BrowserSitePreferenceList.shared
            list.setTranslate(nil, forHost: host)
            if let domain = BrowserSitePreferenceStore.normalizedDomain(for: host) {
                for item in list.items where item.translate != nil && domain.hasSuffix("." + item.domain) {
                    list.setTranslate(nil, forHost: item.domain)
                }
            }
            AppLogger.shared.log("🌐 [BypassBrowser] Bỏ chỉnh riêng tự dịch QT ⇒ theo cấu hình tiện ích")
            store.reapplyTranslationPolicy(for: tab)
        }
    }
}
