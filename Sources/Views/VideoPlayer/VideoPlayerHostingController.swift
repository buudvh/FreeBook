import SwiftUI
import UIKit

/// Host của `VideoPlayerScreen` khi presenter mở lại trình phát (hub / PiP), trình bày `.overFullScreen` (giữ màn bên
/// dưới sống). Trả `VideoOrientationLock.supportedMask` để UIKit dùng khi nó hỏi VC được trình bày phủ kín màn; không
/// chắc mọi phiên bản iOS đều hỏi VC `.overFullScreen` ⇒ khoá xoay vẫn dựa thêm vào bộ dự phòng theo hướng máy của
/// `VideoOrientationLock` (giống đường `fullScreenCover`). Thanh trạng thái / home indicator để SwiftUI tự lo
/// (`statusBarHidden`, `persistentSystemOverlays` trong màn; presenter bật `modalPresentationCapturesStatusBarAppearance`).
final class VideoPlayerHostingController: UIHostingController<AnyView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        VideoOrientationLock.supportedMask
    }
}
