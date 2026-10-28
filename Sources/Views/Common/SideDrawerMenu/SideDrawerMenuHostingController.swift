import SwiftUI
import UIKit

/// Root view controller của cửa sổ ngăn kéo (`SideDrawerMenuWindowManager`).
///
/// Cửa sổ nổi phủ kín màn có thể được UIKit hỏi về thanh trạng thái, home indicator và hướng xoay. Nếu trả giá trị mặc
/// định thì mở ngăn kéo ở Reader / trình phát video (ẩn thanh trạng thái, khoá xoay) sẽ làm thanh trạng thái hiện lại
/// hoặc xoay sai. Vì vậy các thuộc tính đó được **chuyển tiếp** theo view controller đang quyết định của cửa sổ chính:
/// - Cửa sổ chính = cửa sổ level `.normal` là key (dự phòng: cửa sổ `.normal` đang hiện đầu tiên).
/// - Đi dọc chuỗi `presentedViewController` (bỏ cái đang bị gỡ), lấy cái **cuối cùng** trình bày toàn màn
///   (`.fullScreen` / `.overFullScreen`) hoặc bật `modalPresentationCapturesStatusBarAppearance` — như UIKit làm; sheet
///   thường không giành thanh trạng thái của màn bên dưới.
/// - Thanh trạng thái / home indicator còn theo tiếp `childFor…` của controller đó.
/// - Hướng xoay: trình phát video đang khoá xoay thì trả đúng mask đã khoá (đường `fullScreenCover` của trình phát vẫn
///   báo `.allButUpsideDown` lúc khoá, xem `VideoOrientationLock`).
final class SideDrawerMenuHostingController: UIHostingController<SideDrawerMenuWindowRoot> {
    // Tự trả lời, không để UIKit hỏi tiếp một controller con của cây SwiftUI trong cửa sổ này.
    override var childForStatusBarHidden: UIViewController? { nil }
    override var childForStatusBarStyle: UIViewController? { nil }
    override var childForHomeIndicatorAutoHidden: UIViewController? { nil }

    override var prefersStatusBarHidden: Bool {
        guard let owner = forwardedController(following: { $0.childForStatusBarHidden }) else {
            return super.prefersStatusBarHidden
        }
        return owner.prefersStatusBarHidden
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        guard let owner = forwardedController(following: { $0.childForStatusBarStyle }) else {
            return super.preferredStatusBarStyle
        }
        let style = owner.preferredStatusBarStyle
        guard style == .default else { return style }
        // `.default` tự chọn theo giao diện sáng/tối của cửa sổ đang quyết định — cửa sổ này có thể khác giao diện cửa sổ
        // chính, nên đổi ra kiểu cụ thể theo đúng cửa sổ chính.
        let traits = owner.viewIfLoaded?.window?.traitCollection ?? owner.traitCollection
        return traits.userInterfaceStyle == .dark ? .lightContent : .darkContent
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        guard let owner = forwardedController(following: { $0.childForHomeIndicatorAutoHidden }) else {
            return super.prefersHomeIndicatorAutoHidden
        }
        return owner.prefersHomeIndicatorAutoHidden
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if VideoOrientationLock.isLocked {
            return VideoOrientationLock.supportedMask
        }
        guard let root = mainWindowRootController else {
            return super.supportedInterfaceOrientations
        }
        return Self.fullScreenOwner(from: root).supportedInterfaceOrientations
    }

    // MARK: - Tìm controller đang quyết định của cửa sổ chính

    private func forwardedController(following child: (UIViewController) -> UIViewController?) -> UIViewController? {
        guard let root = mainWindowRootController else { return nil }
        var current = Self.fullScreenOwner(from: root)
        // Giới hạn số bước để một chuỗi `childFor…` vòng không treo luồng chính.
        for _ in 0..<12 {
            guard let next = child(current), next !== current else { break }
            current = next
        }
        return current
    }

    private var mainWindowRootController: UIViewController? {
        let ownWindow = viewIfLoaded?.window
        guard let scene = ownWindow?.windowScene else { return nil }
        let candidates = scene.windows.filter { window in
            window !== ownWindow && window.windowLevel == .normal && !window.isHidden && window.rootViewController != nil
        }
        let mainWindow = candidates.first(where: { $0.isKeyWindow }) ?? candidates.first
        return mainWindow?.rootViewController
    }

    /// Controller trình bày toàn màn cuối cùng trong chuỗi `presentedViewController` (không tính cái đang bị gỡ).
    private static func fullScreenOwner(from root: UIViewController) -> UIViewController {
        var owner = root
        var current = root
        while let presented = current.presentedViewController, !presented.isBeingDismissed {
            if presented.modalPresentationCapturesStatusBarAppearance
                || presented.modalPresentationStyle == .fullScreen
                || presented.modalPresentationStyle == .overFullScreen {
                owner = presented
            }
            current = presented
        }
        return owner
    }
}
