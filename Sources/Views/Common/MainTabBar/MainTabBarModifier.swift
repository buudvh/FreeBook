import SwiftUI
import UIKit

/// `.mainTabBar()` — gắn `MainTabBar` vào **trang gốc** của một tab (1.3.668). Phải gắn **bên trong** `NavigationStack`
/// của tab, lên nội dung trang gốc: trang đẩy vào phủ lên thanh, back là thanh trượt về cùng trang gốc. Gắn ra ngoài
/// `NavigationStack` là thanh nổi trên mọi trang đẩy vào.
///
/// - Thanh hệ thống ẩn ở đây, ở `PageTitleModifier` (mọi kiểu) và ở từng tab của `MainTabView`: giá trị luôn `.hidden`
///   nên đẩy/back không làm SwiftUI ẩn/hiện gì.
/// - `hidesWithKeyboard` (chỉ trang gốc có ô nhập — tab Tiện ích): bàn phím hiện ⇒ bỏ thanh (`safeAreaInset` cưỡi lên
///   trên bàn phím; thanh hệ thống cũ thì nằm sau bàn phím). Chỉ nghe khi trang gốc đang hiện, và trả thanh về ngay lúc
///   bị trang đẩy vào che: bàn phím của trang con mà làm trang gốc bỏ thanh thì lúc back thanh hiện lại giữa nhịp trượt
///   ⇒ giật đúng chỗ cần mượt. Trang gốc không có ô nhập để `false`.
/// - Tab đang chọn đọc từ environment `mainTabSelection` do `MainTabView` truyền xuống.
struct MainTabBarModifier: ViewModifier {
    let hidesWithKeyboard: Bool
    @Environment(\.mainTabSelection) private var selection
    @State private var isKeyboardVisible = false
    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isKeyboardVisible {
                    MainTabBar(selection: selection)
                }
            }
            .onAppear { isOnScreen = true }
            .onDisappear {
                isOnScreen = false
                isKeyboardVisible = false
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                if hidesWithKeyboard && isOnScreen { isKeyboardVisible = true }
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
    /// Thanh tab tự vẽ cho trang gốc của tab. Tab gốc mới phải gắn; trang đẩy vào không gắn gì. Trang gốc có ô nhập
    /// truyền `hidesWithKeyboard: true`.
    func mainTabBar(hidesWithKeyboard: Bool = false) -> some View {
        modifier(MainTabBarModifier(hidesWithKeyboard: hidesWithKeyboard))
    }
}
