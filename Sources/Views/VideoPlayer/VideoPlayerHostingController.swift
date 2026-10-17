import SwiftUI
import UIKit

/// Host của `VideoPlayerScreen` khi presenter mở lại trình phát (hub / PiP): trình bày `.fullScreen` nên chính VC
/// này quyết định hướng xoay ⇒ khoá xoay của trình phát có hiệu lực cứng ở đường này. Thanh trạng thái / home
/// indicator để SwiftUI tự lo (`statusBarHidden`, `persistentSystemOverlays` trong màn).
final class VideoPlayerHostingController: UIHostingController<AnyView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        VideoOrientationLock.supportedMask
    }
}
