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
/// Cài đặt con **"Phồn → giản"** (1.3.684) đứng ngay dưới, thụt vào thẳng chữ "Tự dịch QT", chữ nhỏ hơn một bậc:
/// - Công tắc hiện cờ có hiệu lực (`BrowserTranslatePolicy.convertsTraditional(urlString:)`); luôn hiện và luôn chỉnh
///   được kể cả khi "Tự dịch QT" tắt — nút dịch bấm tay và sheet Dịch QT khi bôi đen cũng dùng nó.
/// - Dòng phụ: "Theo cài đặt chung" / "Bật cho <tên miền>" / "Tắt cho <tên miền>".
/// - Đổi ⇒ ghi giá trị tường minh cho tên miền rồi **dịch lại** các tab đang dịch của tên miền đó
///   (`retranslateTabs(underHosts:)`). Không gọi `reapplyTranslationPolicy`: bật/tắt tay của tab phải giữ nguyên.
/// - "Dùng cài đặt chung" (chỉ khi đang có chỉnh riêng) ⇒ ghi `nil`, xoá cả bản ghi của tên miền cha.
///
/// Ghi qua `BrowserSitePreferenceList` (như chặn QC / bản máy tính) để màn Cài đặt Trình duyệt đồng bộ. Đọc
/// `BrowserSitePreferenceList.shared.items` và `@AppStorage` của công tắc chung trong `body` chỉ để SwiftUI vẽ lại khi
/// bản ghi / cài đặt đổi — store gốc và `UserDefaults` không quan sát được.
struct BrowserShieldTranslateSection: View {
    @ObservedObject var store: BypassBrowserTabStore
    @ObservedObject var tab: BypassBrowserTab
    /// Host trang tab đang hiển thị (`BypassBrowserShieldButton.pageHost(of:)`) — host **ghi** chỉnh riêng.
    let host: String

    @AppStorage(BrowserTranslatePolicy.convertsTraditionalKey) private var globalConvertsTraditional = false

    /// Lề trái của cài đặt con = cột icon 24pt + khoảng 10pt của hàng "Tự dịch QT" ⇒ thẳng với chữ "Tự dịch QT".
    private static let childIndent: CGFloat = 34

    var body: some View {
        // Chỉ để đăng ký phụ thuộc (xem doc của type) — giá trị thật lấy qua `BrowserTranslatePolicy`.
        let _ = BrowserSitePreferenceList.shared.items
        let _ = globalConvertsTraditional
        let resolution = BrowserTranslatePolicy.resolve(urlString: tab.urlString)
        let converts = BrowserTranslatePolicy.convertsTraditional(urlString: tab.urlString)
        let convertOverride = BrowserSitePreferenceStore.shared.preference(forHost: host)?.convertsTraditional

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
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

                convertSubsection(isOn: converts, siteOverride: convertOverride)
                    .padding(.leading, Self.childIndent)
            }

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

    // MARK: - Phồn → giản (cài đặt con)

    private func convertSubsection(isOn: Bool, siteOverride: Bool?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: convertBinding(isOn)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Phồn → giản")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(convertSubtitle(siteOverride: siteOverride))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .tint(.green)

            if siteOverride != nil {
                Button {
                    resetConvertToGlobal()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Dùng cài đặt chung")
                            .font(.system(size: 12.5, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(.white)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func convertSubtitle(siteOverride: Bool?) -> String {
        guard let siteOverride else { return "Theo cài đặt chung" }
        return siteOverride ? "Bật cho \(domainText)" : "Tắt cho \(domainText)"
    }

    /// Cùng kiểu `binding(_:)`: chụp giá trị trong lượt vẽ, ghi qua `MainActor.assumeIsolated`.
    private func convertBinding(_ isOn: Bool) -> Binding<Bool> {
        Binding(
            get: { isOn },
            set: { value in
                guard value != isOn else { return }
                MainActor.assumeIsolated { rememberConvert(value) }
            }
        )
    }

    @MainActor
    private func rememberConvert(_ value: Bool) {
        BrowserSitePreferenceList.shared.setConvertsTraditional(value, forHost: host)
        AppLogger.shared.log("🌐 [BypassBrowser] \(value ? "Bật" : "Tắt") phồn → giản trước khi dịch (nhớ theo tên miền)")
        store.retranslateTabs(underHosts: [host])
    }

    /// Như `resetToExtensionRule`: ghi `nil` cho host và xoá trường phồn → giản của mọi tên miền cha (tra cứu gộp tên
    /// miền cha), các trường khác giữ nguyên; rồi dịch lại tab đang dịch của các tên miền vừa đổi.
    private func resetConvertToGlobal() {
        MainActor.assumeIsolated {
            let list = BrowserSitePreferenceList.shared
            var changedHosts = [host]
            list.setConvertsTraditional(nil, forHost: host)
            if let domain = BrowserSitePreferenceStore.normalizedDomain(for: host) {
                for item in list.items where item.convertsTraditional != nil && domain.hasSuffix("." + item.domain) {
                    list.setConvertsTraditional(nil, forHost: item.domain)
                    changedHosts.append(item.domain)
                }
            }
            AppLogger.shared.log("🌐 [BypassBrowser] Bỏ chỉnh riêng phồn → giản ⇒ theo cài đặt chung")
            store.retranslateTabs(underHosts: changedHosts)
        }
    }
}
