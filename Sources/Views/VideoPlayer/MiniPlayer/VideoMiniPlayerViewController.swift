import SwiftUI
import UIKit

/// Gốc của cửa sổ phim nhỏ (1.3.751, `VideoMiniPlayerWindowManager`). Cây view từ dưới lên:
/// 1. `backdrop` — nền đen phủ màn, chỉ hiện lúc cửa sổ nở lại thành màn xem.
/// 2. `leftEdge` / `rightEdge` / `closeTarget` — vạch mép và vòng ✕, chỉ hiện lúc đang kéo.
/// 3. `playerContainer` (bo góc) — `session.layerView` (một instance suốt đời, chuyển qua lại với màn trình phát) + lớp nút
///    SwiftUI (`VideoMiniPlayerOverlay`).
/// 4. `noticeHost` — dòng báo dưới cửa sổ (`VideoMiniPlayerNotice`).
///
/// Kéo bằng UIKit (tay không trễ theo vòng cập nhật SwiftUI, như hub): thả ⇒ bám mép gần nhất ở độ cao thả tay
/// (`VideoMiniPlayerLayout.snap`); thả trên vòng ✕ ⇒ thu vào vòng rồi `onClose` (dừng hẳn phim).
@MainActor
final class VideoMiniPlayerViewController: UIViewController {
    var onExpand: (() -> Void)?
    var onClose: (() -> Void)?

    private let session: VideoPlaybackSession
    private let backdrop = UIView()
    private let leftEdge = UIView()
    private let rightEdge = UIView()
    private let closeTarget = UIView()
    private let playerContainer = UIView()
    private let layerHost = UIView()
    private var overlayHost: UIHostingController<AnyView>?
    private var noticeHost: UIHostingController<AnyView>?
    private var dragStartFrame: CGRect = .zero
    private var isOverClose = false
    /// Đang nở lại thành màn xem: cả màn chặn chạm (nền đen đang phủ).
    private var isExpanding = false

    init(session: VideoPlaybackSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        backdrop.backgroundColor = .black
        backdrop.alpha = 0
        view.addSubview(backdrop)
        for edge in [leftEdge, rightEdge] {
            edge.backgroundColor = UIColor.white.withAlphaComponent(0.5)
            edge.layer.cornerRadius = 1.5
            edge.alpha = 0
            view.addSubview(edge)
        }
        setupCloseTarget()
        setupPlayerContainer()
        setupNotice()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.frame = view.bounds
        let insets = view.safeAreaInsets
        let top = insets.top + VideoMiniPlayerLayout.topMargin
        let height = max(0, view.bounds.height - insets.bottom - top - VideoMiniPlayerLayout.bottomReserve)
        leftEdge.frame = CGRect(x: 3, y: top, width: 3, height: height)
        rightEdge.frame = CGRect(x: view.bounds.width - 6, y: top, width: 3, height: height)
        closeTarget.frame = VideoMiniPlayerLayout.closeTargetFrame(in: view.bounds, safeInsets: insets)
        closeTarget.layer.cornerRadius = closeTarget.bounds.width / 2
    }

    // MARK: - Dựng view

    private func setupCloseTarget() {
        closeTarget.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        closeTarget.layer.borderWidth = 1.5
        closeTarget.layer.borderColor = UIColor.systemRed.withAlphaComponent(0.8).cgColor
        closeTarget.alpha = 0
        closeTarget.isUserInteractionEnabled = false
        let icon = UIImageView(image: UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)))
        icon.tintColor = .systemRed
        icon.translatesAutoresizingMaskIntoConstraints = false
        closeTarget.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: closeTarget.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: closeTarget.centerYAnchor)
        ])
        view.addSubview(closeTarget)
    }

    private func setupPlayerContainer() {
        playerContainer.backgroundColor = .black
        playerContainer.layer.cornerRadius = VideoMiniPlayerLayout.cornerRadius
        playerContainer.layer.cornerCurve = .continuous
        playerContainer.layer.borderWidth = 0.5
        playerContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        playerContainer.clipsToBounds = true
        layerHost.frame = playerContainer.bounds
        layerHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        layerHost.isUserInteractionEnabled = false
        playerContainer.addSubview(layerHost)

        let overlay = VideoMiniPlayerOverlay(
            session: session,
            onExpand: { [weak self] in self?.onExpand?() },
            onClose: { [weak self] in self?.closeAnimated(toTarget: false) }
        )
        let host = UIHostingController(rootView: AnyView(overlay.appAccentTint()))
        host.view.backgroundColor = .clear
        host.view.frame = playerContainer.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addChild(host)
        playerContainer.addSubview(host.view)
        host.didMove(toParent: self)
        overlayHost = host

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        playerContainer.addGestureRecognizer(pan)
        view.addSubview(playerContainer)
    }

    private func setupNotice() {
        let host = UIHostingController(rootView: AnyView(VideoMiniPlayerNotice(session: session)))
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        noticeHost = host
    }

    // MARK: - Hiện / ẩn

    /// Hiện ở `frame` (toạ độ màn hình) với dáng mặc định rồi nhận hình.
    func present(at frame: CGRect) {
        isExpanding = false
        backdrop.alpha = 0
        playerContainer.alpha = 1
        playerContainer.transform = .identity
        playerContainer.layer.cornerRadius = VideoMiniPlayerLayout.cornerRadius
        overlayHost?.view.alpha = 1
        noticeHost?.view.alpha = 1
        setPlayerFrame(frame)
        adoptLayer()
    }

    /// Đưa `session.layerView` vào cửa sổ (nếu đang nằm chỗ khác) — trừ khi màn to đang gắn (màn đó giữ hình).
    func adoptLayer() {
        guard !session.isFullScreenAttached else { return }
        let layerView = session.layerView
        guard layerView.superview !== layerHost else { return }
        layerView.removeFromSuperview()
        layerView.frame = layerHost.bounds
        layerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        layerHost.addSubview(layerView)
    }

    /// Trả hình (cửa sổ ẩn). Hình đã sang màn khác thì thôi.
    func releaseLayer() {
        let layerView = session.layerView
        guard layerView.superview === layerHost else { return }
        layerView.removeFromSuperview()
    }

    func acceptsTouch(on view: UIView) -> Bool {
        if isExpanding { return true }
        return view.isDescendant(of: playerContainer)
    }

    // MARK: - Nở lại

    /// Nở lên chỗ khung phim của màn xem, nền đen phủ dần; `completion` mở màn xem (không animation).
    func animateExpand(to frame: CGRect, completion: @escaping () -> Void) {
        isExpanding = true
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) {
            self.backdrop.alpha = 1
            self.overlayHost?.view.alpha = 0
            self.noticeHost?.view.alpha = 0
            self.playerContainer.layer.cornerRadius = 0
            self.setPlayerFrame(frame)
        } completion: { _ in
            completion()
        }
    }

    /// Không mở được màn xem ⇒ thu về chỗ đậu.
    func collapse(to frame: CGRect) {
        UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
            self.backdrop.alpha = 0
            self.overlayHost?.view.alpha = 1
            self.noticeHost?.view.alpha = 1
            self.playerContainer.layer.cornerRadius = VideoMiniPlayerLayout.cornerRadius
            self.setPlayerFrame(frame)
        } completion: { _ in
            self.isExpanding = false
        }
    }

    // MARK: - Kéo

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .began:
            dragStartFrame = playerContainer.frame
            isOverClose = false
            setDragChrome(visible: true)
        case .changed:
            setPlayerFrame(dragStartFrame.offsetBy(dx: translation.x, dy: translation.y))
            updateDragChrome()
        case .ended, .cancelled, .failed:
            setDragChrome(visible: false)
            if gesture.state == .ended, isOverClose {
                closeAnimated(toTarget: true)
                return
            }
            let snapped = VideoMiniPlayerLayout.snap(
                playerContainer.frame,
                velocityX: gesture.velocity(in: view).x,
                in: view.bounds,
                safeInsets: view.safeAreaInsets
            )
            UIView.animate(
                withDuration: 0.34, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.setPlayerFrame(snapped)
            }
        default:
            break
        }
    }

    private func setDragChrome(visible: Bool) {
        UIView.animate(withDuration: 0.18) {
            self.closeTarget.alpha = visible ? 1 : 0
            self.leftEdge.alpha = visible ? 1 : 0
            self.rightEdge.alpha = visible ? 1 : 0
            if !visible {
                self.closeTarget.transform = .identity
            }
        }
        if visible { updateDragChrome() }
    }

    private func updateDragChrome() {
        let frame = playerContainer.frame
        let nearest = VideoMiniPlayerLayout.nearestEdge(of: frame, in: view.bounds)
        let accent = AppAccentColor.current.uiColor
        leftEdge.backgroundColor = nearest == .left ? accent : UIColor.white.withAlphaComponent(0.35)
        rightEdge.backgroundColor = nearest == .right ? accent : UIColor.white.withAlphaComponent(0.35)
        let over = VideoMiniPlayerLayout.isOverCloseTarget(frame, in: view.bounds, safeInsets: view.safeAreaInsets)
        guard over != isOverClose else { return }
        isOverClose = over
        if over { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        UIView.animate(withDuration: 0.15) {
            self.closeTarget.transform = over ? CGAffineTransform(scaleX: 1.25, y: 1.25) : .identity
            self.closeTarget.backgroundColor = over
                ? UIColor.systemRed.withAlphaComponent(0.85)
                : UIColor.black.withAlphaComponent(0.6)
            self.playerContainer.alpha = over ? 0.6 : 1
        }
    }

    /// ✕ của cửa sổ, hoặc thả vào vòng ✕ (`toTarget`): thu nhỏ rồi tắt hẳn phim.
    private func closeAnimated(toTarget: Bool) {
        let end = toTarget ? closeTarget.center : CGPoint(x: playerContainer.frame.midX, y: playerContainer.frame.midY)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn]) {
            self.playerContainer.center = end
            self.playerContainer.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            self.playerContainer.alpha = 0
            self.noticeHost?.view.alpha = 0
        } completion: { _ in
            self.onClose?()
        }
    }

    // MARK: - Khung

    private func setPlayerFrame(_ frame: CGRect) {
        playerContainer.transform = .identity
        playerContainer.frame = frame
        let noticeWidth = min(view.bounds.width - 16, max(frame.width, 240))
        let noticeX = min(max(8, frame.midX - noticeWidth / 2), view.bounds.width - 8 - noticeWidth)
        noticeHost?.view.frame = CGRect(x: noticeX, y: frame.maxY + 6, width: noticeWidth, height: 30)
    }
}
