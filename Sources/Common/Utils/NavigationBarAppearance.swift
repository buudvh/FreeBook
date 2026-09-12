import UIKit

/// Bỏ **chữ** ở nút back của mọi thanh điều hướng, chỉ chừa mũi chevron.
///
/// iOS 17 không có `navigationBarBackButtonDisplayMode(.minimal)` (API iOS 18), nên cách duy nhất
/// áp một lần cho toàn app là sửa `UINavigationBar.appearance()`: đặt màu chữ của
/// `backButtonAppearance` thành trong suốt. Chỉ nhắm đúng nút back — dùng
/// `UIBarButtonItem.appearance()` sẽ xoá luôn chữ của "Đóng"/"Xong"/"Huỷ" ở toolbar.
///
/// **Phải tạo `UINavigationBarAppearance()` mới, không đọc rồi sửa tại chỗ.** Appearance proxy
/// (`UINavigationBar.appearance()`) chỉ bảo đảm hợp đồng cho *setter*; getter của nó không trả về
/// đối tượng đang có hiệu lực, nên `proxy.standardAppearance` đọc ra rồi sửa là sửa vào hư không —
/// đó là lý do lần cài đặt đầu không có tác dụng.
///
/// Vì vậy phải tự dựng lại đúng ba trạng thái mặc định của UIKit để không đổi diện mạo thanh:
/// `standard`/`compact` dùng nền mờ (`configureWithDefaultBackground`), còn hai trạng thái scroll
/// edge dùng nền trong suốt (`configureWithTransparentBackground`) — đúng mặc định iOS 15+.
enum NavigationBarAppearance {
    static func applyTitlelessBackButton() {
        let proxy = UINavigationBar.appearance()

        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        hideBackButtonTitle(in: standard)
        proxy.standardAppearance = standard

        let compact = UINavigationBarAppearance()
        compact.configureWithDefaultBackground()
        hideBackButtonTitle(in: compact)
        proxy.compactAppearance = compact

        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        hideBackButtonTitle(in: scrollEdge)
        proxy.scrollEdgeAppearance = scrollEdge

        let compactScrollEdge = UINavigationBarAppearance()
        compactScrollEdge.configureWithTransparentBackground()
        hideBackButtonTitle(in: compactScrollEdge)
        proxy.compactScrollEdgeAppearance = compactScrollEdge
    }

    /// Màu trong suốt cho **cả bốn** trạng thái: bỏ sót trạng thái nào thì chữ hiện lại đúng lúc
    /// người dùng đang nhấn giữ nút. Kèm cỡ chữ 0.1pt để nhãn không còn chiếm chỗ, nếu không
    /// chevron sẽ lệch hẳn sang trái so với tiêu đề.
    private static func hideBackButtonTitle(in appearance: UINavigationBarAppearance) {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.clear,
            .font: UIFont.systemFont(ofSize: 0.1)
        ]
        appearance.backButtonAppearance.normal.titleTextAttributes = attributes
        appearance.backButtonAppearance.highlighted.titleTextAttributes = attributes
        appearance.backButtonAppearance.disabled.titleTextAttributes = attributes
        appearance.backButtonAppearance.focused.titleTextAttributes = attributes
    }
}
