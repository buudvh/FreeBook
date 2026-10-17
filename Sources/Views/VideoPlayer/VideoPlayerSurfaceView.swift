import SwiftUI
import AVFoundation
import UIKit

/// Khung hình của trình phát: nhận `VideoPlayerLayerView` của session (một instance suốt đời, PiP gắn vào nó) và chuyển
/// vào container của mình. Không giữ player — dựng lại view này (đổi bố cục dọc ↔ toàn màn, mở lại màn) không làm
/// gián đoạn phát.
struct VideoPlayerSurfaceView: UIViewRepresentable {
    let layerView: VideoPlayerLayerView
    let gravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        container.isUserInteractionEnabled = false
        adopt(into: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        adopt(into: container)
        if layerView.playerLayer.videoGravity != gravity {
            layerView.playerLayer.videoGravity = gravity
        }
    }

    static func dismantleUIView(_ container: UIView, coordinator: ()) {
        // Màn mới (mở lại) có thể đã nhận layer trước khi màn cũ gỡ xong ⇒ chỉ gỡ khi layer còn nằm trong container này.
        for subview in container.subviews where subview is VideoPlayerLayerView {
            subview.removeFromSuperview()
        }
    }

    private func adopt(into container: UIView) {
        guard layerView.superview !== container else { return }
        layerView.removeFromSuperview()
        layerView.frame = container.bounds
        layerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(layerView)
    }
}
