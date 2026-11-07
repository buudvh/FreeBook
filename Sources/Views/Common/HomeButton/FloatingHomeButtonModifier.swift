import SwiftUI
import UIKit

/// **Nút Home nổi riêng** của trang con: nút tròn 52pt nền kính góc dưới phải (cùng thông số nút "+" nổi, theo Cài đặt ›
/// Giao diện), icon `house`, bấm ⇒ về trang gốc của tab đang đứng. `PageTitleModifier` gắn modifier này ở **mọi** trang
/// (mọi kiểu tiêu đề) nên trang mới tự có; hiện hay không do cây UIKit quyết định lúc chạy — luật ở
/// `FloatingHomePlacement`.
///
/// - Trang có nút "+" nổi (`.floatingAddButton`) hoặc FAB riêng (`.floatingHomeHostedByPage()`, FAB Chi tiết) ⇒ không vẽ
///   nút này: Home là pill **dưới cùng** trong menu xổ của nút "+" (`FloatingHomeRegistry`).
/// - Vẽ bằng `overlay`, **không** `safeAreaInset`: điều kiện chỉ có sau một nhịp nên inset sẽ đẩy nội dung giật sau khi
///   trang đã hiện, và inset cưỡi lên bàn phím. Đổi lại nút có thể đè phần cuối góc phải của trang.
/// - Bàn phím hiện ⇒ ẩn (trang con có ô nhập, thanh gợi ý bàn phím), theo mẫu của `MainTabBarModifier`.
struct FloatingHomeButtonModifier: ViewModifier {
    @State private var token = UUID()
    @State private var placement: FloatingHomePlacement?
    @State private var isKeyboardVisible = false
    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        content
            .background {
                FloatingHomeProbe(token: token, role: .pageTitle) { placement = $0 }
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomTrailing) {
                if !isKeyboardVisible, let action = standaloneAction {
                    FloatingRoundButton(systemImage: "house", accessibilityLabel: FloatingActionItem.homeTitle) {
                        action()
                    }
                    .padding(.trailing, FloatingRoundButton.trailingInset)
                    .padding(.bottom, FloatingRoundButton.bottomInset)
                }
            }
            .onAppear { isOnScreen = true }
            .onDisappear {
                isOnScreen = false
                isKeyboardVisible = false
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                if isOnScreen { isKeyboardVisible = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
    }

    /// Hành động của nút tròn riêng — `nil` khi trang không đủ điều kiện, khi Home đã nằm trong nút "+" / FAB của trang,
    /// hoặc khi trang có tiêu đề khác đã vẽ Home.
    @MainActor
    private var standaloneAction: (@MainActor () -> Void)? {
        guard let placement, let action = placement.homeAction else { return nil }
        let registry = FloatingHomeRegistry.shared
        guard !registry.hasAddButton(on: placement.hostID),
              registry.drawsPageTitleHome(token, on: placement.hostID) else { return nil }
        return action
    }
}

extension View {
    /// Nút Home nổi riêng — `PageTitleModifier` đã tự gắn; chỉ gắn tay cho trang không dùng tiêu đề chuẩn.
    func floatingHomeButton() -> some View {
        modifier(FloatingHomeButtonModifier())
    }

    /// Trang **tự** đặt Home trong nút nổi của nó (FAB riêng, không phải `.floatingAddButton`) ⇒ tiêu đề không vẽ Home
    /// tròn riêng. Gắn lên view của FAB (view thật, không rỗng); FAB tự đọc `FloatingHomeReader` để biết có hiện pill Home.
    func floatingHomeHostedByPage() -> some View {
        FloatingHomeReader(role: .addButton) { _ in self }
    }
}
