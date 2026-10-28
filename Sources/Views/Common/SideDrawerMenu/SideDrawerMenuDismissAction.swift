import SwiftUI

/// Điều khiển ngăn kéo cho các hàng bên trong — `SideDrawerMenuPanel` cài vào environment:
/// - `callAsFunction(then:)`: đóng ngăn kéo; action chạy **ngay** khi ngăn kéo bắt đầu trượt ra.
/// - `refreshContent()`: hàng công tắc / hàng chọn vừa đổi giá trị ⇒ vẽ lại nội dung ngăn kéo theo state mới của màn.
///
/// Ngoài ngăn kéo (giá trị mặc định) action chạy ngay và `refreshContent()` không làm gì, nên một hàng lỡ dùng ở chỗ
/// khác vẫn hoạt động.
struct SideDrawerMenuDismissAction {
    let handler: ((() -> Void)?) -> Void
    /// Đổi mỗi lần panel được yêu cầu vẽ lại ⇒ giá trị environment đổi, các hàng đọc nó chạy lại `body` và đọc lại
    /// Binding của màn.
    let revision: Int
    let refresher: () -> Void

    init(
        handler: @escaping ((() -> Void)?) -> Void,
        revision: Int = 0,
        refresher: @escaping () -> Void = {}
    ) {
        self.handler = handler
        self.revision = revision
        self.refresher = refresher
    }

    /// Đóng ngăn kéo; `followUp` chạy ngay khi ngăn kéo bắt đầu trượt ra (cửa sổ ngăn kéo không chặn màn bên dưới
    /// trình bày sheet / hộp thoại).
    func callAsFunction(then followUp: (() -> Void)? = nil) {
        handler(followUp)
    }

    /// Vẽ lại nội dung ngăn kéo sau khi một hàng đổi giá trị (ngăn kéo vẫn mở).
    func refreshContent() {
        refresher()
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
