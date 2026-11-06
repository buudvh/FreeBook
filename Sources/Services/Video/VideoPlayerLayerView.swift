import UIKit
import AVFoundation

/// `UIView` có `AVPlayerLayer` làm layer gốc.
///
/// `VideoPlaybackSession` giữ **một** instance suốt đời: màn trình phát (`VideoPlayerSurfaceView`) và cửa sổ nhỏ
/// (`VideoMiniPlayerViewController`) chỉ chuyển view này vào khung của mình, không tự dựng layer riêng ⇒ thu nhỏ / mở lại
/// không ngắt phim.
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
