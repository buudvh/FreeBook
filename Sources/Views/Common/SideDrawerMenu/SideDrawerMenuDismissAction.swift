import SwiftUI

/// "Đóng ngăn kéo rồi mới chạy action" — `SideDrawerMenuPanel` cài vào environment cho các hàng bên trong.
///
/// Ngoài ngăn kéo (giá trị mặc định) action chạy ngay, nên một hàng lỡ dùng ở chỗ khác vẫn hoạt động.
struct SideDrawerMenuDismissAction {
    let handler: ((() -> Void)?) -> Void

    /// Đóng ngăn kéo; `followUp` chạy sau khi ngăn kéo đã gỡ hẳn khỏi màn hình.
    func callAsFunction(then followUp: (() -> Void)? = nil) {
        handler(followUp)
    }

    /// Khoá environment lồng trong type (một type chính mỗi file). `defaultValue` là thuộc tính tính toán để không có
    /// biến tĩnh lưu closure.
    struct Key: EnvironmentKey {
        static var defaultValue: SideDrawerMenuDismissAction {
            SideDrawerMenuDismissAction { followUp in
                followUp?()
            }
        }
    }
}

extension EnvironmentValues {
    var sideDrawerMenuDismiss: SideDrawerMenuDismissAction {
        get { self[SideDrawerMenuDismissAction.Key.self] }
        set { self[SideDrawerMenuDismissAction.Key.self] = newValue }
    }
}
