import UIKit

/// Bỏ **chữ** ở nút back của mọi thanh điều hướng, chỉ chừa mũi chevron.
///
/// iOS 17 không có `navigationBarBackButtonDisplayMode(.minimal)` (API iOS 18), nên cách duy nhất
/// áp một lần cho toàn app là sửa `UINavigationBar.appearance()`: đặt màu chữ của
/// `backButtonAppearance` thành trong suốt. Chỉ nhắm đúng nút back — dùng
/// `UIBarButtonItem.appearance()` sẽ xoá luôn chữ của "Đóng"/"Xong"/"Huỷ" ở toolbar.
///
/// Sửa **tại chỗ** đối tượng appearance đang có (không tạo `UINavigationBarAppearance()` mới) để
/// giữ nguyên nền mờ mặc định của thanh điều hướng; `compactAppearance`/`scrollEdgeAppearance` chỉ
/// được chạm khi app đã tự khai, `nil` thì để UIKit tự suy ra từ `standardAppearance`.
enum NavigationBarAppearance {
    static func applyTitlelessBackButton() {
        let proxy = UINavigationBar.appearance()

        let standard = proxy.standardAppearance
        hideBackButtonTitle(in: standard)
        proxy.standardAppearance = standard

        if let compact = proxy.compactAppearance {
            hideBackButtonTitle(in: compact)
            proxy.compactAppearance = compact
        }
        if let scrollEdge = proxy.scrollEdgeAppearance {
            hideBackButtonTitle(in: scrollEdge)
            proxy.scrollEdgeAppearance = scrollEdge
        }
        if let compactScrollEdge = proxy.compactScrollEdgeAppearance {
            hideBackButtonTitle(in: compactScrollEdge)
            proxy.compactScrollEdgeAppearance = compactScrollEdge
        }
    }

    /// Màu trong suốt cho **cả bốn** trạng thái: bỏ sót trạng thái nào thì chữ hiện lại đúng lúc
    /// người dùng đang nhấn giữ nút.
    private static func hideBackButtonTitle(in appearance: UINavigationBarAppearance) {
        let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.clear]
        appearance.backButtonAppearance.normal.titleTextAttributes = attributes
        appearance.backButtonAppearance.highlighted.titleTextAttributes = attributes
        appearance.backButtonAppearance.disabled.titleTextAttributes = attributes
        appearance.backButtonAppearance.focused.titleTextAttributes = attributes
    }
}
