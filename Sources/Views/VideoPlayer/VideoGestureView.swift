import UIKit
import MediaPlayer
import AVFoundation

/// Bắt cử chỉ trên khung phim bằng UIKit (chạm 1 lần chờ chạm đúp thất bại; hướng vuốt quyết định lúc bắt đầu):
/// - Chạm 1 lần: ẩn/hiện điều khiển. Chạm đúp nửa trái/phải: lùi/tới.
/// - Vuốt ngang: tua có xem trước. Vuốt dọc: toàn màn thì trái = độ sáng, phải = âm lượng hệ thống; khung dọc nhỏ thì
///   vuốt xuống = thu nhỏ (tránh đụng cử chỉ thu nhỏ).
/// - Nhấn giữ: tạm phát 2×.
///
/// Âm lượng hệ thống chỉ chỉnh được qua `UISlider` của `MPVolumeView` ⇒ giữ một `MPVolumeView` gần như trong suốt
/// (alpha 0.01, không `isHidden` — ẩn hẳn thì không chỉnh được và iOS hiện HUD âm lượng của hệ thống).
///
/// Độ sáng là của cả máy, iOS không tự trả lại khi rời app ⇒ chụp độ sáng gốc ở lần vuốt đầu và trả lại khi view rời
/// cửa sổ (đóng / thu nhỏ trình phát, chuyển sang trang nhúng) hoặc app mất active (`willResignActive`).
final class VideoGestureView: UIView {
    enum Side {
        case leading
        case trailing
    }

    enum PanKind {
        case seek
        case brightness
        case volume
        case dismiss
    }

    enum VerticalMode {
        /// Toàn màn / ngang: độ sáng & âm lượng.
        case levels
        /// Khung 16:9 ở màn dọc: vuốt xuống để thu nhỏ.
        case dismiss
    }

    struct Handlers {
        var singleTap: (Side) -> Void = { _ in }
        var doubleTap: (Side) -> Void = { _ in }
        var panBegan: (PanKind) -> Void = { _ in }
        /// `seek`: tỉ lệ dịch ngang / bề rộng (âm = lùi); `brightness`/`volume`: mức mới 0…1; `dismiss`: điểm dịch dọc.
        var panChanged: (PanKind, CGFloat) -> Void = { _, _ in }
        var panEnded: (PanKind, CGFloat) -> Void = { _, _ in }
        var longPress: (Bool) -> Void = { _ in }
    }

    var handlers = Handlers()
    var verticalMode: VerticalMode = .dismiss
    /// Khoá cảm ứng: chỉ còn chạm 1 lần (để hiện nút mở khoá).
    var isTouchLocked = false

    private let volumeView = MPVolumeView(frame: CGRect(x: -200, y: -200, width: 40, height: 40))
    private var activePan: PanKind?
    private var panStartLevel: CGFloat = 0
    /// Độ sáng trước lần vuốt đầu tiên (kèm màn hình đã chỉnh); `nil` = chưa chỉnh hoặc đã trả lại.
    private var originalBrightness: (screen: UIScreen, value: CGFloat)?
    private lazy var singleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
    private lazy var doubleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
    private lazy var panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private lazy var longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        volumeView.alpha = 0.01
        volumeView.isUserInteractionEnabled = false
        addSubview(volumeView)

        doubleTapRecognizer.numberOfTapsRequired = 2
        singleTapRecognizer.require(toFail: doubleTapRecognizer)
        panRecognizer.maximumNumberOfTouches = 1
        longPressRecognizer.minimumPressDuration = 0.5
        for recognizer in [singleTapRecognizer, doubleTapRecognizer, panRecognizer, longPressRecognizer] as [UIGestureRecognizer] {
            addGestureRecognizer(recognizer)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { restoreOriginalBrightness() }
    }

    @objc private func handleWillResignActive() {
        restoreOriginalBrightness()
    }

    // MARK: - Lọc cử chỉ

    /// `UIView` hỏi hàm này cho mọi recognizer gắn vào nó.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isTouchLocked else { return true }
        return gestureRecognizer === singleTapRecognizer
    }

    // MARK: - Xử lý

    @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        handlers.singleTap(side(of: recognizer))
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        handlers.doubleTap(side(of: recognizer))
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            handlers.longPress(true)
        case .ended, .cancelled, .failed:
            handlers.longPress(false)
        default:
            break
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        switch recognizer.state {
        case .began:
            let kind = panKind(for: recognizer)
            activePan = kind
            switch kind {
            case .brightness:
                rememberOriginalBrightness()
                panStartLevel = currentBrightness
            case .volume: panStartLevel = CGFloat(AVAudioSession.sharedInstance().outputVolume)
            case .seek, .dismiss: break
            }
            handlers.panBegan(kind)
        case .changed:
            guard let kind = activePan else { return }
            handlers.panChanged(kind, value(for: kind, translation: translation))
        case .ended, .cancelled, .failed:
            guard let kind = activePan else { return }
            activePan = nil
            let finished = recognizer.state == .ended
            handlers.panEnded(kind, finished ? value(for: kind, translation: translation) : 0)
        default:
            break
        }
    }

    private func panKind(for recognizer: UIPanGestureRecognizer) -> PanKind {
        let velocity = recognizer.velocity(in: self)
        if abs(velocity.x) > abs(velocity.y) { return .seek }
        if verticalMode == .dismiss { return .dismiss }
        return recognizer.location(in: self).x < bounds.midX ? .brightness : .volume
    }

    private func value(for kind: PanKind, translation: CGPoint) -> CGFloat {
        switch kind {
        case .seek:
            return bounds.width > 0 ? translation.x / bounds.width : 0
        case .dismiss:
            return translation.y
        case .brightness, .volume:
            // Vuốt hết ~80% chiều cao = đi trọn thang 0…1.
            let span = max(bounds.height * 0.8, 1)
            let level = min(1, max(0, panStartLevel - translation.y / span))
            apply(level: level, kind: kind)
            return level
        }
    }

    private func side(of recognizer: UIGestureRecognizer) -> Side {
        recognizer.location(in: self).x < bounds.midX ? .leading : .trailing
    }

    // MARK: - Độ sáng / âm lượng

    private var currentBrightness: CGFloat {
        window?.windowScene?.screen.brightness ?? 0.5
    }

    private func rememberOriginalBrightness() {
        guard originalBrightness == nil, let screen = window?.windowScene?.screen else { return }
        originalBrightness = (screen: screen, value: screen.brightness)
    }

    private func restoreOriginalBrightness() {
        guard let original = originalBrightness else { return }
        originalBrightness = nil
        original.screen.brightness = original.value
    }

    private func apply(level: CGFloat, kind: PanKind) {
        switch kind {
        case .brightness:
            window?.windowScene?.screen.brightness = level
        case .volume:
            guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
            slider.setValue(Float(level), animated: false)
            slider.sendActions(for: .valueChanged)
        case .seek, .dismiss:
            break
        }
    }
}
