import SwiftUI

/// Hai hàng **ngang hàng, độc lập** trong bảng khiên (mockup 2026-10-30, màn "Mới 3"; tách phồn → giản 1.3.846):
/// "Tự dịch QT" và "Phồn → giản". Mỗi hàng có công tắc + dòng phụ + nút trả về luật gốc riêng.
///
/// **Tự dịch QT** — nhớ tự dịch theo tên miền:
/// - Công tắc hiện **luật nhớ** (`BrowserTranslatePolicy.resolve(urlString:).isEnabled`), không phải trạng thái dịch
///   của tab (cái đó còn tính nút dịch bấm tay, không ghi nhớ).
/// - Dòng phụ theo nguồn quyết định: "Đang theo tiện ích <tên>" / "Bật cho <tên miền>" / "Tắt cho <tên miền>" /
///   "Chưa bật".
/// - Đổi công tắc ⇒ luôn ghi giá trị **tường minh** cho tên miền của tab (như mockup: bấm là thành "Bật/Tắt cho …" và
///   hiện dòng "Dùng cấu hình tiện ích"), rồi `reapplyTranslationPolicy` để trang dịch/khôi phục ngay, không nạp lại.
/// - "Dùng cấu hình tiện ích" (chỉ khi đang có chỉnh riêng) ⇒ ghi `nil`.
///
/// **Phồn → giản** — bước riêng, chạy cả khi không dịch (bật mà không dịch ⇒ trang hiện giản thể):
/// - Công tắc hiện cờ có hiệu lực (`BrowserTranslatePolicy.convertsTraditional(urlString:)`); luôn chỉnh được.
/// - Dòng phụ: "Theo cài đặt chung" / "Bật cho <tên miền>" / "Tắt cho <tên miền>".
/// - Đổi ⇒ ghi giá trị tường minh cho tên miền rồi áp lại cho **mọi** tab của tên miền đó
///   (`reapplyConvertPolicy(underHosts:)`). Không gọi `reapplyTranslationPolicy`: bật/tắt tay dịch của tab giữ nguyên.
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

    var body: some View {
        // Chỉ để đăng ký phụ thuộc (xem doc của type) — giá trị thật lấy qua `BrowserTranslatePolicy`.
        let _ = BrowserSitePreferenceList.shared.items
        let _ = globalConvertsTraditional
        let resolution = BrowserTranslatePolicy.resolve(urlString: tab.urlString)
        let converts = BrowserTranslatePolicy.convertsTraditional(urlString: tab.urlString)
        let convertOverride = BrowserSitePreferenceStore.shared.preference(forHost: host)?.convertsTraditional

        VStack(alignment: .leading, spacing: 12) {
            toggleRow(title: "Tự dịch QT", subtitle: subtitle(for: resolution), isOn: binding(resolution.isEnabled)) {
                AppGlyph.translate.image(size: 18)
            }
            if resolution.siteOverride != nil {
                resetButton("Dùng cấu hình tiện ích", action: resetToExtensionRule)
            }

            toggleRow(
                title: "Phồn → giản",
                subtitle: convertSubtitle(siteOverride: convertOverride),
                isOn: convertBinding(converts)
            ) {
                Image(systemName: "textformat")
                    .font(.system(size: 15, weight: .semibold))
            }
            if convertOverride != nil {
                resetButton("Dùng cài đặt chung", action: resetConvertToGlobal)
            }
        }
    }

    // MARK: - Khung hàng

    /// Hàng công tắc: cột icon 24pt + tiêu đề 14pt nửa đậm + dòng phụ; hai hàng của section dùng chung.
    private func toggleRow<Icon: View>(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        let iconView = icon()
        return Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                iconView
                    .foregroundColor(.white)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .tint(.green)
    }

    private func resetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundColor(.white)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var domainText: String {
        BrowserSitePreferenceStore.normalizedDomain(for: host) ?? host
    }

    // MARK: - Tự dịch QT

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
    /// không có tác dụng. Chỉ xoá trường dịch, chặn QC / bản máy tính / phồn → giản của tên miền cha giữ nguyên.
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

    // MARK: - Phồn → giản

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
        AppLogger.shared.log("🌐 [BypassBrowser] \(value ? "Bật" : "Tắt") phồn → giản (nhớ theo tên miền)")
        store.reapplyConvertPolicy(underHosts: [host])
    }

    /// Như `resetToExtensionRule`: ghi `nil` cho host và xoá trường phồn → giản của mọi tên miền cha (tra cứu gộp tên
    /// miền cha), các trường khác giữ nguyên; rồi áp lại cho tab của các tên miền vừa đổi.
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
            store.reapplyConvertPolicy(underHosts: changedHosts)
        }
    }
}
