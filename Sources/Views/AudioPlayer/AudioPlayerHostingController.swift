import SwiftUI
import UIKit

/// Host của `AudioPlayerScreen` khi `AudioPlayerPresenter` trình bày bằng UIKit (`.overFullScreen`, màn bên dưới vẫn
/// sống). Màn nghe **chỉ dọc** — UIKit hỏi VC được trình bày phủ kín màn (không chắc mọi phiên bản iOS đều hỏi VC
/// `.overFullScreen`, nên bố cục màn nghe vẫn chịu được màn ngang). Đường `fullScreenCover` của router do SwiftUI giữ VC,
/// không đọc giá trị này.
final class AudioPlayerHostingController: UIHostingController<AnyView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }
}
