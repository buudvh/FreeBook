import Foundation

/// Nguồn **duy nhất** của luật ưu tiên chặn quảng cáo / chế độ máy tính cho webview. Hàm thuần, gọi được từ
/// thread bất kỳ (đọc `UserDefaults`, `BrowserSitePreferenceStore` có lock, và bảng chụp `nonisolated` của
/// `ExtensionLibraryRepository`).
///
/// - Trình duyệt người dùng: chặn QC = `site.adBlock ?? chung`; máy tính = `site.desktop ?? mặc định trình duyệt`.
/// - Webview tiện ích: chặn QC = `ext.adBlockOverride ?? chung`; máy tính = `ext.desktopModeOverride ?? false`
///   (**không** theo mặc định máy tính của trình duyệt — chế độ máy tính đổi HTML trang trả về, dễ làm hỏng bóc tách).
/// - Ngoài phạm vi: không gắn luật, điện thoại.
///
/// Chặn cửa sổ bật lên không thuộc đây: chỉ đọc `WebContentSettings.popupBlockingEnabled` (không theo tên miền,
/// không theo tiện ích). UA do tiện ích tự khai thắng chế độ máy tính — xử lý ở `WebContentConfigurator`.
enum WebContentPolicy {
    static func decision(for context: WebContentContext) -> WebContentDecision {
        switch context {
        case .userBrowser(let host):
            let site = BrowserSitePreferenceStore.shared.preference(forHost: host)
            return WebContentDecision(
                adBlock: site?.adBlock ?? WebContentSettings.adBlockEnabled,
                desktop: site?.desktop ?? WebContentSettings.browserDefaultDesktop
            )
        case .extensionContent(let packageId):
            let ext = packageId.flatMap { ExtensionLibraryRepository.snapshot(packageId: $0) }
            return WebContentDecision(
                adBlock: ext?.adBlockOverride ?? WebContentSettings.adBlockEnabled,
                desktop: ext?.desktopModeOverride ?? false
            )
        case .excluded:
            return WebContentDecision(adBlock: false, desktop: false)
        }
    }

    /// Cho webview tạo từ `JSExecutor` (có `localPath` của tiện ích). `nil` ⇒ `.excluded` (webview không thuộc
    /// tiện ích nào, vd đăng nhập Gemini qua `VisibleWebViewLoader`); có path ⇒ tra `packageId` qua bảng chụp.
    static func decision(forExtensionLocalPath path: String?) -> WebContentDecision {
        guard let path else { return decision(for: .excluded) }
        return decision(for: .extensionContent(packageId: ExtensionLibraryRepository.packageId(forLocalPath: path)))
    }
}
