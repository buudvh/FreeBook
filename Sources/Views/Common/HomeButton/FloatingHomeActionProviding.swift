import UIKit

/// Lối **tường minh** bật nút Home nổi cho trang trình bày bằng UIKit, ngoài cây tab (vd trang đè lên màn xem phim của
/// `VideoWatchPagePresenter`). VC được present — gốc của tầng trình bày — conform protocol này ⇒ mọi trang trong tầng đó,
/// **kể cả** trang đầu của `NavigationStack` riêng, hiện Home; bấm Home (nút tròn hoặc pill trong menu xổ của nút "+")
/// thì gọi `performFloatingHome()`. Xem luật đầy đủ ở `FloatingHomePlacement`.
///
/// Vì sao không dùng environment: giá trị environment chảy cả vào sheet / cover mở từ trong trang (sheet tải/xuất, trình
/// duyệt của Chi tiết…), mà ở đó Home bị cấm (lách `confirmDiscardOnSwipe` làm mất chỉnh sửa chưa lưu). Sheet lồng bên
/// trong có gốc trình bày riêng, không conform ⇒ tự không có Home.
///
/// ```swift
/// private final class PortraitHostingController: UIHostingController<AnyView>, FloatingHomeActionProviding {
///     func performFloatingHome() {
///         dismiss(animated: true) { MainTabNavigationEvents.shared.send(.showCurrentTabRoot) }
///     }
/// }
/// ```
@MainActor
protocol FloatingHomeActionProviding: AnyObject {
    /// Người dùng bấm Home ở một trang thuộc tầng trình bày này.
    func performFloatingHome()
}
