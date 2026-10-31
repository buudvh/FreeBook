import SwiftUI
import UIKit

/// `.mainTabBar()` — gắn `MainTabBar` vào **trang gốc** của một tab (1.3.668). Phải gắn **bên trong** `NavigationStack`
/// của tab, lên nội dung trang gốc: trang đẩy vào phủ lên thanh, back là thanh trượt về cùng trang gốc. Gắn ra ngoài
/// `NavigationStack` là thanh nổi trên mọi trang đẩy vào.
///
/// - Thanh hệ thống ẩn ở đây, ở `PageTitleModifier` (mọi kiểu) và ở từng tab của `MainTabView`: giá trị luôn `.hidden`
///   nên đẩy/back không làm SwiftUI ẩn/hiện gì.
/// - Bàn phím hiện ⇒ bỏ thanh (`safeAreaInset` cưỡi lên trên bàn phím; thanh hệ thống cũ thì nằm sau bàn phím).
/// - Tab đang chọn đọc từ environment `mainTabSelection` do `MainTabView` truyền xuống.
struct MainTabBarModifier: ViewModifier {
    @Environment(\.mainTabSelection) private var selection
    @State private var isKeyboardVisible = false

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isKeyboardVisible {
                    MainTabBar(selection: selection)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
    }

    /// Khoá environment lồng trong type (một type chính mỗi file). Mặc định là binding hằng: preview / màn không nằm
    /// trong `MainTabView` vẫn vẽ được thanh, chỉ là chạm không đổi tab.
    struct SelectionKey: EnvironmentKey {
        static var defaultValue: Binding<Int> { .constant(0) }
    }
}

extension EnvironmentValues {
    /// Tab đang chọn của `MainTabView` — chỉ `MainTabBarModifier` đọc.
    var mainTabSelection: Binding<Int> {
        get { self[MainTabBarModifier.SelectionKey.self] }
        set { self[MainTabBarModifier.SelectionKey.self] = newValue }
    }
}

extension View {
    /// Thanh tab tự vẽ cho trang gốc của tab. Tab gốc mới phải gắn; trang đẩy vào không gắn gì.
    func mainTabBar() -> some View {
        modifier(MainTabBarModifier())
    }
}
