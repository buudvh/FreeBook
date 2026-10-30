import Foundation

/// Nguồn **duy nhất** của luật nhớ tự dịch QT cho trình duyệt người dùng. Thứ tự ưu tiên:
/// 1. Chỉnh riêng theo tên miền (`BrowserSitePreferenceStore.preference(forHost:)?.translate`, công tắc trong bảng khiên).
/// 2. Tiện ích **đầu tiên** theo thứ tự `ExtensionUrlMatcher.matches` (trên `ExtensionUrlMatcher.candidates` của bản cài)
///    có `Extension.translateOverride != nil` (công tắc ở Cấu hình tiện ích › Trình duyệt).
/// 3. **Mặc định** của tiện ích khớp URL đầu tiên (`defaultTranslate(for:)`): cấu hình dịch "Nguồn này" của Reader
///    (`TranslationConfigStore`) nếu đã đặt, không thì nguồn tiếng Trung (`Extension.isChineseSource`) ⇒ bật.
/// 4. Tắt.
///
/// Nút dịch trên thanh trình duyệt **không** đi qua đây (chỉ bật/tắt cho tab đang xem, không ghi nhớ).
///
/// `@MainActor` vì đọc `ExtensionLibraryRepository.shared.installed` (View gọi trong `body` thì Observation tự vẽ lại
/// khi bảng tiện ích đổi). Chỉ dò `regexp` của tiện ích **có thể** quyết định (có công tắc, nguồn tiếng Trung, hoặc đã
/// cấu hình dịch nguồn) nên mỗi lần commit trang không biên dịch regex của mọi tiện ích.
@MainActor
enum BrowserTranslatePolicy {
    static func resolve(urlString: String) -> BrowserTranslateResolution {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return .disabled
        }
        if let siteOverride = BrowserSitePreferenceStore.shared.preference(forHost: host)?.translate {
            return BrowserTranslateResolution(isEnabled: siteOverride, source: .site, siteOverride: siteOverride)
        }
        // Lọc trước khi dò (giữ nguyên thứ tự ứng viên): tiện ích không thể tự dịch thì khỏi chạy regex của nó.
        let candidates = ExtensionUrlMatcher.candidates(from: ExtensionLibraryRepository.shared.installed)
            .filter { $0.translateOverride != nil || hasTranslateDefault($0) }
        guard !candidates.isEmpty else { return .disabled }
        let matches = ExtensionUrlMatcher.matches(for: urlString, in: candidates)
        if let match = matches.first(where: { $0.ext.translateOverride != nil }), let value = match.ext.translateOverride {
            return BrowserTranslateResolution(isEnabled: value, source: .`extension`(name: match.ext.name), siteOverride: nil)
        }
        if let match = matches.first {
            return BrowserTranslateResolution(
                isEnabled: defaultTranslate(for: match.ext),
                source: .`extension`(name: match.ext.name),
                siteOverride: nil
            )
        }
        return .disabled
    }

    /// Mặc định khi tiện ích chưa bật/tắt "Tự dịch trang (QT)": cấu hình dịch "Nguồn này" của Reader nếu đã đặt, không thì
    /// theo ngôn ngữ nguồn (tiếng Trung ⇒ bật). Màn Cấu hình tiện ích dùng để hiện giá trị đang có hiệu lực của công tắc.
    nonisolated static func defaultTranslate(for ext: Extension) -> Bool {
        TranslationConfigStore.shared.resolveStatus(
            bookId: nil,
            packageId: ext.packageId,
            isChineseSourceHint: ext.isChineseSource
        ).isEnabled
    }

    /// Tiện ích có thể tự bật dịch dù chưa chỉnh công tắc: nguồn tiếng Trung, hoặc đã cấu hình dịch "Nguồn này".
    private static func hasTranslateDefault(_ ext: Extension) -> Bool {
        ext.isChineseSource || TranslationConfigStore.shared.getSourceOverride(packageId: ext.packageId) != .inherited
    }
}
