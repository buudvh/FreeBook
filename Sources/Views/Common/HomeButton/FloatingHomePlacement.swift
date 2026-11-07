import UIKit

/// Vị trí của một trang trong cây UIKit — đủ để quyết định có hiện **nút Home nổi** không (`homeAction`). Dựng bởi
/// `FloatingHomeProbe` từ một `UIView` 0×0 nằm trong trang; quyết định theo **ngữ cảnh lúc chạy**, không theo đường dẫn
/// file (vd `QuickTranslationRuleListView` ở `Views/Settings/` nhưng được đẩy trong tab Kệ ⇒ có Home).
///
/// Luật:
/// - **Cây tab**: gốc tầng của trang **không** phải màn được present (sheet, cover, UIKit `present` đều loại), trang là
///   trang **đẩy vào** (khác trang đầu của `UINavigationController` chứa nó) và thuộc tab Kệ Sách (0), Khám Phá (1) hoặc
///   Tiện Ích (2). Chỉ số tab là tab **sở hữu** ngăn xếp (đi `parent` tới con trực tiếp của `UITabBarController`), không
///   phải `selectedIndex`. Bấm ⇒ `MainTabNavigationEvents.send(.showCurrentTabRoot)`.
/// - **Tầng trình bày có provider**: gốc tầng là màn được present và conform `FloatingHomeActionProviding` ⇒ hiện ở mọi
///   trang của tầng (kể cả trang đầu), bấm ⇒ provider tự lo.
/// - Còn lại không hiện: trang gốc các tab, tab Cài Đặt, Reader / truyện tranh / phim và mọi trang đẩy trong chúng (đều
///   nằm trong `fullScreenCover`), sheet / form / trình soạn, trình duyệt, cửa sổ hub / widget (không có thanh tab).
///
/// `hostID` = **trang** chứa view: VC tổ tiên gần nhất là con trực tiếp của một `UINavigationController` (SwiftUI có thể
/// lồng hosting controller con), không có nav thì chính VC gần nhất. Nút "+" và tiêu đề của cùng một trang ra cùng
/// `hostID` ⇒ `FloatingHomeRegistry` ghép được chúng bất kể thứ tự modifier.
struct FloatingHomePlacement: Equatable {
    /// Tab có nút Home: Kệ Sách, Khám Phá, Tiện Ích (thứ tự = `tag` của `MainTabView`).
    static let homeTabs: ClosedRange<Int> = 0...2

    let hostID: ObjectIdentifier
    /// Tab sở hữu trang; `nil` = không nằm dưới `UITabBarController`.
    let tabIndex: Int?
    let isPushed: Bool
    /// Gốc tầng của trang là màn được present (sheet / cover / UIKit present).
    let isPresented: Bool
    /// Gốc tầng trình bày, khi nó conform `FloatingHomeActionProviding`.
    private(set) weak var provider: (any FloatingHomeActionProviding)?
    private let providerID: ObjectIdentifier?

    init(
        hostID: ObjectIdentifier,
        tabIndex: Int?,
        isPushed: Bool,
        isPresented: Bool,
        provider: (any FloatingHomeActionProviding)?
    ) {
        self.hostID = hostID
        self.tabIndex = tabIndex
        self.isPushed = isPushed
        self.isPresented = isPresented
        self.provider = provider
        self.providerID = provider.map { ObjectIdentifier($0) }
    }

    /// Hành động của nút Home trên trang này; `nil` = không hiện Home.
    var homeAction: (@MainActor () -> Void)? {
        if isPresented {
            guard providerID != nil, let provider else { return nil }
            return { [weak provider] in provider?.performFloatingHome() }
        }
        guard isPushed, let tabIndex, Self.homeTabs.contains(tabIndex) else { return nil }
        return { MainTabNavigationEvents.shared.send(.showCurrentTabRoot) }
    }

    static func == (lhs: FloatingHomePlacement, rhs: FloatingHomePlacement) -> Bool {
        lhs.hostID == rhs.hostID
            && lhs.tabIndex == rhs.tabIndex
            && lhs.isPushed == rhs.isPushed
            && lhs.isPresented == rhs.isPresented
            && lhs.providerID == rhs.providerID
    }

    /// Đọc vị trí trang chứa `view` (`page` = VC của trang, để đăng ký với `FloatingHomeRegistry`). `nil` khi view chưa
    /// nằm dưới VC nào (chưa gắn xong / cửa sổ không có VC).
    @MainActor
    static func resolve(from view: UIView) -> (placement: FloatingHomePlacement, page: UIViewController)? {
        var responder: UIResponder? = view
        while let current = responder, !(current is UIViewController) {
            responder = current.next
        }
        guard let nearest = responder as? UIViewController else { return nil }

        var page: UIViewController?
        var isPushed = false
        var tabIndex: Int?
        var layerRoot = nearest
        var current: UIViewController? = nearest
        while let controller = current {
            if let navigation = controller.parent as? UINavigationController {
                if page == nil { page = controller }
                if navigation.viewControllers.first !== controller { isPushed = true }
            }
            if tabIndex == nil, let tabBar = controller.parent as? UITabBarController {
                tabIndex = tabBar.viewControllers?.firstIndex(of: controller)
            }
            layerRoot = controller
            current = controller.parent
        }

        let isPresented = layerRoot.presentingViewController != nil
        let resolvedPage = page ?? nearest
        let placement = FloatingHomePlacement(
            hostID: ObjectIdentifier(resolvedPage),
            tabIndex: tabIndex,
            isPushed: isPushed,
            isPresented: isPresented,
            provider: isPresented ? layerRoot as? any FloatingHomeActionProviding : nil
        )
        return (placement, resolvedPage)
    }
}
