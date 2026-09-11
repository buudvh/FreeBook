import UIKit

/// Diện mạo thanh điều hướng và tab bar cho **chế độ E-Ink**.
///
/// Trên e-ink, `configureWithDefaultBackground()` (nền mờ + backdrop blur) render ra vệt xám nhoè và
/// làm chữ khó đọc, nên chế độ này chuyển cả hai thanh sang **nền trắng đục + đường kẻ đen 1px**. Kể cả
/// bốn trạng thái scroll-edge cũng đổi sang đục: để một trạng thái trong suốt thì thanh sẽ tự nhiên mờ
/// đi đúng lúc người dùng cuộn — chính là lúc cần tương phản nhất.
///
/// **Appearance proxy của UIKit không retroactive**: `apply()` chỉ ảnh hưởng thanh *chưa* dựng. Đó là lý
/// do `EInkModeSettings.setEnabled` gọi lại hàm này; và cũng là lý do đổi chế độ có thể cần mở lại màn
/// mới thấy thanh đổi — đã ghi rõ trong `EInkSettingsSection`.
enum EInkAppearance {

    static func apply() {
        if EInkModeSettings.shared.isEnabled {
            applyEInk()
        } else {
            applyDefault()
        }
    }

    /// Nền đục + kẻ đen cho cả bốn trạng thái của nav bar, và nền đục cho tab bar.
    private static func applyEInk() {
        let navProxy = UINavigationBar.appearance()

        // `shadowColor` chính là đường kẻ dưới thanh điều hướng — đặt đen để thành hairline thật.
        let standard = makeOpaqueNavigationAppearance()
        navProxy.standardAppearance = standard
        navProxy.compactAppearance = standard

        let scrollEdge = makeOpaqueNavigationAppearance()
        navProxy.scrollEdgeAppearance = scrollEdge
        navProxy.compactScrollEdgeAppearance = scrollEdge

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = EInkPalette.paperUIColor
        tab.shadowColor = EInkPalette.inkUIColor
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    private static func makeOpaqueNavigationAppearance() -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = EInkPalette.paperUIColor
        appearance.shadowColor = EInkPalette.inkUIColor
        // Phải áp lại: `configureWithOpaqueBackground()` dựng appearance mới nên mọi thứ đã đặt trước đó
        // (kể cả việc ẩn chữ ở nút back) đều mất.
        NavigationBarAppearance.hideBackButtonTitle(in: appearance)
        return appearance
    }

    /// Trả hai thanh về đúng mặc định mà `FreeBookApp.init()` đã đặt — đây là đường đi khi người dùng
    /// **tắt** chế độ, nên phải khôi phục chứ không được để sót cấu hình đục.
    private static func applyDefault() {
        NavigationBarAppearance.applyTitlelessBackButton()

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}
