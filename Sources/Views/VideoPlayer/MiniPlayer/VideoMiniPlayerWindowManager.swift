import UIKit

/// Cửa sổ phim **nhỏ trong app** (1.3.751, thay Hình trong hình của hệ thống) — đích của kiểu thu nhỏ "Cửa sổ nhỏ" khi
/// vuốt xuống khung phim, và của nút "Cửa sổ nhỏ" trên thanh trên của trình phát.
///
/// - `UIWindow` riêng ở level `alert - 2.5` (dưới hub `alert - 2`, trên widget trình duyệt `alert - 3`): nổi trên mọi màn
///   kể cả khi đang đọc truyện; chạm ngoài cửa sổ rơi xuống app (`VideoMiniPlayerUIWindow`). Không phải level `.normal`
///   ⇒ `VideoPlayerPresenter.findTopViewController` không bao giờ trình bày lên nó.
/// - Gắn vào phiên như một màn (`attachScreen(_:isMiniPlayer: true)`): hình vẫn gắn player, dòng Video của hub ẩn, phim
///   không ngắt vì cửa sổ nhận đúng `session.layerView` từ màn trình phát.
/// - Tự ẩn khi màn to gắn lại (`onFullScreenAttached`) hoặc phiên dừng hẳn (`onDidStop`, xét ở nhịp main sau: tự sang
///   phim đề xuất `stop()` rồi mở phim mới ngay trong cùng nhịp — cửa sổ phải ở lại).
/// - Chạm ⇒ nở lên chỗ khung phim của màn xem rồi mở lại màn **không animation** (`requestScreen(animated: false)`).
/// - Tắt NSFW lúc phát phim 18+, hoặc rời app (công tắc `VideoLeaveAppPolicy`, mặc định bật) ⇒ thu vào hub như thả lên nút
///   hub, phim phát tiếp (`VideoLeaveToHubCoordinator`, đăng ký lúc hiện, gỡ lúc ẩn). Công tắc rời app tắt ⇒ cửa sổ ở lại,
///   phim chỉ phát tiếng (session tách hình khi vào nền).
@MainActor
final class VideoMiniPlayerWindowManager {
    static let shared = VideoMiniPlayerWindowManager()

    private var window: VideoMiniPlayerUIWindow?
    private var controller: VideoMiniPlayerViewController?
    private(set) var isShowing = false
    private var session: VideoPlaybackSession { VideoPlaybackSession.shared }

    private init() {}

    /// Kích thước + vùng an toàn của màn chính (cửa sổ `.normal` của scene chính).
    static func screenMetrics() -> (bounds: CGRect, safeInsets: UIEdgeInsets) {
        let scene = AppMainWindowScene.current()
        let mainWindow = scene?.windows.first { $0.windowLevel == .normal && !($0 is AppOverlayWindow) }
        let bounds = mainWindow?.bounds ?? scene?.screen.bounds ?? .zero
        return (bounds, mainWindow?.safeAreaInsets ?? .zero)
    }

    /// Chỗ đậu hiện tại (toạ độ màn hình) — đích của hiệu ứng co khung phim.
    func dockFrame() -> CGRect {
        let metrics = Self.screenMetrics()
        return VideoMiniPlayerLayout.dockFrame(in: metrics.bounds, safeInsets: metrics.safeInsets)
    }

    // MARK: - Hiện / ẩn

    /// Hiện cửa sổ ở `frame` (thường = `dockFrame()` mà khung phim vừa co tới) và nhận hình. Gọi **trước** khi màn trình
    /// phát đóng ⇒ phiên luôn có màn gắn, hub không thoáng hiện dòng Video.
    func show(at frame: CGRect) {
        guard session.isActive, session.embedContent == nil else {
            AppLogger.shared.log("⚠️ [VideoMini] Không mở cửa sổ nhỏ: phiên rảnh hoặc phim nhúng trang")
            return
        }
        guard let controller = ensureWindow() else {
            AppLogger.shared.log("❌ [VideoMini] Không tìm được scene chính để mở cửa sổ nhỏ")
            return
        }
        session.onFullScreenAttached = { [weak self] in
            self?.hide(reason: "màn trình phát đã mở lại")
        }
        session.onDidStop = {
            // Tự sang phim đề xuất dừng phim cũ rồi mở phim mới trong cùng nhịp ⇒ chỉ ẩn khi phiên vẫn rảnh ở nhịp sau.
            // Singleton ⇒ đọc qua `shared`, không bắt `weak self` vào closure lồng.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let manager = VideoMiniPlayerWindowManager.shared
                    guard manager.isShowing, !manager.session.isActive else { return }
                    manager.hide(reason: "phim đã tắt")
                }
            }
        }
        VideoLeaveToHubCoordinator.shared.register(self) { reason, _ in
            // Nút Home của trang đè lên màn xem chỉ thu phim **của màn đó**; cửa sổ nhỏ (phim khác) giữ nguyên.
            guard reason != .homeButton else { return false }
            // Rời app: không nảy nút hub (đang ở nền).
            VideoMiniPlayerWindowManager.shared.collapseToHub(
                reason: "\(reason.logLabel) ⇒ thu vào hub",
                bounces: reason != .appBackground
            )
            return false
        }
        window?.isHidden = false
        isShowing = true
        controller.present(at: frame)
        session.attachScreen(controller, isMiniPlayer: true)
        reclaimLayerSoon()
        AppLogger.shared.log("🎬 [VideoMini] Thu nhỏ thành cửa sổ nhỏ")
    }

    func hide(reason: String) {
        guard isShowing, let controller else { return }
        isShowing = false
        VideoLeaveToHubCoordinator.shared.unregister(self)
        controller.releaseLayer()
        window?.isHidden = true
        session.onFullScreenAttached = nil
        session.onDidStop = nil
        session.detachScreen(controller)
        AppLogger.shared.log("🎬 [VideoMini] Ẩn cửa sổ nhỏ (\(reason))")
    }

    /// Màn trình phát đang đóng (không animation) có thể vẽ lại một nhịp và lấy lại hình ⇒ nhận lại hình sau khi màn đó đã
    /// đi hẳn. `adoptLayer` tự bỏ qua khi màn to đang gắn.
    private func reclaimLayerSoon() {
        for delay in [0.1, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated {
                    let manager = VideoMiniPlayerWindowManager.shared
                    guard manager.isShowing else { return }
                    manager.controller?.adoptLayer()
                }
            }
        }
    }

    // MARK: - Chạm / tắt

    private func expand() {
        guard isShowing, let controller else { return }
        let metrics = Self.screenMetrics()
        let target = VideoMiniPlayerLayout.expandedVideoFrame(in: metrics.bounds, safeInsets: metrics.safeInsets)
        AppLogger.shared.log("🎬 [VideoMini] Chạm cửa sổ nhỏ ⇒ mở lại màn xem")
        controller.animateExpand(to: target) {
            VideoMiniPlayerWindowManager.shared.session.requestScreen(animated: false) {
                // Màn xem gắn vào phiên thì cửa sổ tự ẩn (`onFullScreenAttached`). Chưa gắn sau một nhịp ⇒ không mở được.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    MainActor.assumeIsolated {
                        let manager = VideoMiniPlayerWindowManager.shared
                        guard manager.isShowing, !manager.session.isFullScreenAttached else { return }
                        AppLogger.shared.log("❌ [VideoMini] Không mở lại được màn xem ⇒ thu cửa sổ về chỗ đậu")
                        manager.controller?.collapse(to: manager.dockFrame())
                    }
                }
            }
        }
    }

    /// Thả cửa sổ lên nút hub (1.3.765): như nút ⌄ của màn to — phim chạy tiếp chỉ tiếng, hub hiện dòng Video.
    private func minimizeToHub() {
        AppLogger.shared.log("🎬 [VideoMini] Kéo cửa sổ nhỏ vào hub ⇒ phim chạy nền")
        collapseToHub(reason: "thu vào hub", bounces: true)
    }

    /// Thu cửa sổ vào hub, phim phát tiếp (không bao giờ dừng ở đây): thả lên nút hub, hoặc theo
    /// `VideoLeaveToHubCoordinator`. Cửa sổ đang ẩn ⇒ bỏ qua (gọi lặp an toàn).
    func collapseToHub(reason: String, bounces: Bool) {
        guard isShowing else { return }
        session.noteMinimizing()
        FloatingHubWindowManager.shared.setDropTargetHighlighted(false)
        hide(reason: reason)
        if bounces {
            FloatingHubWindowManager.shared.bounceButton()
        }
    }

    private func close() {
        AppLogger.shared.log("🎬 [VideoMini] Tắt phim từ cửa sổ nhỏ")
        session.stop()
        // `stop()` gọi `onDidStop` (ẩn ở nhịp sau); phòng khi phiên đã rảnh từ trước.
        if !session.isActive { hide(reason: "phim đã tắt") }
    }

    // MARK: - Cửa sổ

    private func ensureWindow() -> VideoMiniPlayerViewController? {
        guard let scene = AppMainWindowScene.current() else { return nil }
        if let window, let controller, window.windowScene === scene {
            window.frame = scene.coordinateSpace.bounds
            return controller
        }
        window?.isHidden = true
        let controller = VideoMiniPlayerViewController(session: session)
        controller.onExpand = { [weak self] in self?.expand() }
        controller.onClose = { [weak self] in self?.close() }
        controller.onMinimizeToHub = { [weak self] in self?.minimizeToHub() }
        let win = VideoMiniPlayerUIWindow(windowScene: scene)
        win.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue - 2.5)
        win.backgroundColor = .clear
        win.miniPlayerController = controller
        win.rootViewController = controller
        win.frame = scene.coordinateSpace.bounds
        window = win
        self.controller = controller
        controller.loadViewIfNeeded()
        win.layoutIfNeeded()
        return controller
    }
}
