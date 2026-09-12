import UIKit

/// Diện mạo thanh điều hướng và tab bar cho **chế độ E-Ink**.
///
/// Trên e-ink, `configureWithDefaultBackground()` (nền mờ + backdrop blur) render ra vệt xám nhoè và
/// làm chữ khó đọc, nên chế độ này chuyển cả hai thanh sang **nền trắng đục + đường kẻ đen 1px**. Kể cả
/// bốn trạng thái scroll-edge cũng đổi sang đục: để một trạng thái trong suốt thì thanh sẽ tự nhiên mờ
/// đi đúng lúc người dùng cuộn — chính là lúc cần tương phản nhất.
///
/// **Appearance proxy của UIKit không retroactive**: `apply()` vẫn cài proxy cho thanh dựng sau, đồng thời
/// duyệt các window hiện có để thanh đang mở đổi ngay khi người dùng bật/tắt hoặc đổi màu nền giấy.
enum EInkAppearance {

    static func apply() {
        if Thread.isMainThread {
            applyOnMainThread()
        } else {
            DispatchQueue.main.async {
                applyOnMainThread()
            }
        }
    }

    private static func applyOnMainThread() {
        let config = EInkModeSettings.shared.isEnabled ? makeEInkConfiguration() : makeDefaultConfiguration()
        install(config)
        applyToExistingBars(config)
    }

    private struct Configuration {
        let navigationStandard: UINavigationBarAppearance
        let navigationCompact: UINavigationBarAppearance
        let navigationScrollEdge: UINavigationBarAppearance
        let navigationCompactScrollEdge: UINavigationBarAppearance
        let tab: UITabBarAppearance
    }

    private static func install(_ config: Configuration) {
        let navProxy = UINavigationBar.appearance()
        navProxy.standardAppearance = config.navigationStandard
        navProxy.compactAppearance = config.navigationCompact
        navProxy.scrollEdgeAppearance = config.navigationScrollEdge
        navProxy.compactScrollEdgeAppearance = config.navigationCompactScrollEdge

        UITabBar.appearance().standardAppearance = config.tab
        UITabBar.appearance().scrollEdgeAppearance = config.tab
    }

    /// Nền đục + kẻ đen cho cả bốn trạng thái của nav bar, và nền đục cho tab bar.
    private static func makeEInkConfiguration() -> Configuration {
        let standard = makeOpaqueNavigationAppearance()
        let compact = makeOpaqueNavigationAppearance()
        let scrollEdge = makeOpaqueNavigationAppearance()
        let compactScrollEdge = makeOpaqueNavigationAppearance()

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = EInkPalette.paperUIColor
        tab.shadowColor = EInkPalette.inkUIColor

        return Configuration(
            navigationStandard: standard,
            navigationCompact: compact,
            navigationScrollEdge: scrollEdge,
            navigationCompactScrollEdge: compactScrollEdge,
            tab: tab
        )
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
    private static func makeDefaultConfiguration() -> Configuration {
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        NavigationBarAppearance.hideBackButtonTitle(in: standard)

        let compact = UINavigationBarAppearance()
        compact.configureWithDefaultBackground()
        NavigationBarAppearance.hideBackButtonTitle(in: compact)

        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        NavigationBarAppearance.hideBackButtonTitle(in: scrollEdge)

        let compactScrollEdge = UINavigationBarAppearance()
        compactScrollEdge.configureWithTransparentBackground()
        NavigationBarAppearance.hideBackButtonTitle(in: compactScrollEdge)

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()

        return Configuration(
            navigationStandard: standard,
            navigationCompact: compact,
            navigationScrollEdge: scrollEdge,
            navigationCompactScrollEdge: compactScrollEdge,
            tab: tab
        )
    }

    /// `UIAppearance` chỉ tác động view dựng sau. Duyệt window hiện tại để đổi ngay khi người dùng bật/tắt
    /// hoặc đổi màu nền E-Ink, không cần đóng mở app/tab.
    private static func applyToExistingBars(_ config: Configuration) {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { apply(config, in: $0) }
    }

    private static func apply(_ config: Configuration, in view: UIView) {
        if let navigationBar = view as? UINavigationBar {
            navigationBar.standardAppearance = config.navigationStandard
            navigationBar.compactAppearance = config.navigationCompact
            navigationBar.scrollEdgeAppearance = config.navigationScrollEdge
            navigationBar.compactScrollEdgeAppearance = config.navigationCompactScrollEdge
            navigationBar.setNeedsLayout()
        }

        if let tabBar = view as? UITabBar {
            tabBar.standardAppearance = config.tab
            tabBar.scrollEdgeAppearance = config.tab
            tabBar.setNeedsLayout()
        }

        view.subviews.forEach { apply(config, in: $0) }
    }
}
