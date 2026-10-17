import UIKit
import AVFoundation

/// `UIView` có `AVPlayerLayer` làm layer gốc.
///
/// `VideoPlaybackSession` giữ **một** instance suốt đời: PiP (`AVPictureInPictureController`) gắn với chính layer này,
/// nên layer phải sống qua lúc màn hình bị gỡ (thu nhỏ). Màn hình chỉ chuyển view này vào khung của nó
/// (`VideoPlayerSurfaceView`), không tự dựng layer riêng.
final class VideoPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    /// `layerClass` bảo đảm kiểu ⇒ ép kiểu không bao giờ thất bại.
    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .black
        // Cử chỉ do lớp phủ phía trên xử lý; view hình không nhận chạm.
        isUserInteractionEnabled = false
        playerLayer.videoGravity = .resizeAspect
    }
}
