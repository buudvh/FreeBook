import UIKit

/// Xoay và khoá xoay của trình phát video.
///
/// - Nút **Xoay**: `requestGeometryUpdate` sang ngang/dọc ngay, không cần nghiêng máy. Hướng giữ nguyên tới khi máy
///   được xoay thật.
/// - **Khoá xoay**: `supportedMask` chỉ còn hướng hiện tại.
///   - `VideoPlayerHostingController` (đường mở lại từ hub / cửa sổ nhỏ, trình bày `.overFullScreen`) trả mask này — có hiệu
///     lực khi UIKit hỏi VC được trình bày; không chắc với mọi phiên bản iOS nên vẫn có dự phòng bên dưới.
///   - Đường `fullScreenCover` của router do SwiftUI giữ view controller, không đọc mask ⇒ dự phòng (cả hai đường):
///     máy xoay khi đang khoá thì xin lại hướng đã khoá (có thể thấy giật một nhịp). Muốn khoá cứng mọi đường, app
///     delegate trả `VideoOrientationLock.supportedMask` trong `application(_:supportedInterfaceOrientationsFor:)`.
///   - Khoá ở ngang rồi bấm Xoay dọc thì khoá theo dọc; nút khoá xoay vẫn hiện khi đang khoá (`VideoPlayerTopBar`)
///     để mở khoá được ở màn dọc.
@MainActor
enum VideoOrientationLock {
    /// Hướng được phép khi đang khoá; `nil` = theo cảm biến.
    private(set) static var lockedMask: UIInterfaceOrientationMask?
    private static var deviceObserver: NSObjectProtocol?

    static var supportedMask: UIInterfaceOrientationMask { lockedMask ?? .allButUpsideDown }

    static var isLocked: Bool { lockedMask != nil }

    static func setLocked(_ locked: Bool) {
        if locked {
            let current = activeScene?.interfaceOrientation ?? .portrait
            lockedMask = orientationMask(for: current)
            startFallbackObserver()
            AppLogger.shared.log("🔒 [VideoPlayer] Khoá xoay")
        } else {
            lockedMask = nil
            stopFallbackObserver()
        }
        refreshSupportedOrientations()
    }

    /// Đổi dọc ↔ ngang ngay. Đang khoá thì khoá theo hướng mới.
    static func rotate(toLandscape: Bool) {
        let target: UIInterfaceOrientationMask
        if toLandscape {
            // Máy đang nghiêng sẵn về phía nào thì xoay theo phía đó; không thì mặc định tai thỏ bên trái.
            target = UIDevice.current.orientation == .landscapeRight ? .landscapeLeft : .landscapeRight
        } else {
            target = .portrait
        }
        if lockedMask != nil {
            lockedMask = target
        }
        request(target)
    }

    /// Rời trình phát: bỏ khoá; đang ngang thì trả về dọc để phần còn lại của app không nằm ngang. Luôn báo UIKit hỏi lại
    /// hướng được phép (1.3.781): màn xem rời đi thì trang chỉ dọc nằm dưới nó (`VideoWatchPagePresenter`) lấy lại `.portrait`.
    static func resetForExit() {
        let wasLandscape = activeScene?.interfaceOrientation.isLandscape ?? false
        if lockedMask != nil {
            lockedMask = nil
            stopFallbackObserver()
        }
        if wasLandscape {
            request(.portrait)
        } else {
            refreshSupportedOrientations()
        }
    }

    static var isInterfaceLandscape: Bool {
        activeScene?.interfaceOrientation.isLandscape ?? false
    }

    // MARK: - Nội bộ

    /// Scene chứa giao diện chính (`AppMainWindowScene`) — xoay nhầm scene của PiP thì màn trình phát không xoay.
    private static var activeScene: UIWindowScene? {
        AppMainWindowScene.current()
    }

    /// Báo UIKit hỏi lại hướng được phép **trước** mỗi lần xin xoay (1.3.781): UIKit giữ mask cũ tới khi được báo — vd màn
    /// xem mở lại đè lên trang chỉ dọc mà mask còn `.portrait` của trang ⇒ xin ngang bị từ chối.
    private static func request(_ mask: UIInterfaceOrientationMask) {
        guard let scene = activeScene else { return }
        refreshSupportedOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            AppLogger.shared.log("❌ [VideoPlayer] Không xoay được màn hình: \(error.localizedDescription)")
        }
    }

    /// Báo mọi VC của các cửa sổ trong scene chính hỏi lại hướng được phép. Gọi thêm sau khi trình bày xong màn xem
    /// (`VideoWatchPresenter`) — màn có thể nằm trên trang chỉ dọc, nghiêng máy thật cũng phải xoay được.
    static func refreshSupportedOrientations() {
        guard let scene = activeScene else { return }
        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
        }
    }

    private static func orientationMask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .portrait
        }
    }

    // MARK: - Dự phòng cho đường fullScreenCover

    private static func startFallbackObserver() {
        guard deviceObserver == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        deviceObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                VideoOrientationLock.scheduleFallbackCheck()
            }
        }
    }

    private static func stopFallbackObserver() {
        guard let observer = deviceObserver else { return }
        NotificationCenter.default.removeObserver(observer)
        deviceObserver = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    /// Chờ hệ thống xoay xong rồi mới so: lệch khỏi hướng đã khoá thì xin lại.
    private static func scheduleFallbackCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            MainActor.assumeIsolated {
                guard let mask = VideoOrientationLock.lockedMask,
                      let current = VideoOrientationLock.activeScene?.interfaceOrientation,
                      !mask.contains(VideoOrientationLock.orientationMask(for: current)) else { return }
                VideoOrientationLock.request(mask)
            }
        }
    }
}
