import SwiftUI
import UIKit

/// Các bước cuối của hiệu ứng thu nhỏ trình phát (1.3.751) — `VideoPlayerScreen` gọi, đóng màn (không animation) ở
/// `completion` khi khung phim đã tới đích:
/// - `flyToHub`: khung phim bay nhỏ dần vào nút hub rồi tan, hub nháy một nhịp (kiểu "Thu nhỏ vào hub", nút ⌄).
/// - `dockToMiniPlayer`: khung phim co đúng vào chỗ đậu của cửa sổ nhỏ, cửa sổ hiện ra nhận hình rồi màn mới đóng
///   (thứ tự này giữ phiên luôn có màn gắn ⇒ hub không thoáng hiện dòng Video).
/// - `springBack`: nhả tay chưa tới ngưỡng ⇒ về như cũ.
@MainActor
enum VideoMinimizeAnimator {
    private static let hubDuration: TimeInterval = 0.3
    private static let dockDuration: TimeInterval = 0.32
    /// Khung đích nhỏ (16:9) ở chỗ nút hub.
    private static let hubTargetSize = CGSize(width: 48, height: 27)

    /// Nhả tay đủ xa, hoặc hất nhanh xuống ⇒ thu nhỏ.
    static func shouldCommit(translation: CGFloat, velocity: CGFloat) -> Bool {
        translation > 110 || (velocity > 900 && translation > 24)
    }

    static func springBack(_ drag: VideoMinimizeDragState) {
        withAnimation(.spring(duration: 0.32, bounce: 0.12)) {
            drag.cancel()
        }
    }

    static func flyToHub(_ drag: VideoMinimizeDragState, completion: @escaping () -> Void) {
        let target = hubTargetFrame()
        withAnimation(.easeIn(duration: hubDuration)) {
            drag.commit(to: target, fadesOut: true)
        } completion: {
            completion()
            FloatingHubWindowManager.shared.bounceButton()
        }
    }

    static func dockToMiniPlayer(_ drag: VideoMinimizeDragState, completion: @escaping () -> Void) {
        let target = VideoMiniPlayerWindowManager.shared.dockFrame()
        withAnimation(.spring(duration: dockDuration, bounce: 0)) {
            drag.commit(to: target, fadesOut: false)
        } completion: {
            VideoMiniPlayerWindowManager.shared.show(at: target)
            completion()
        }
    }

    /// Nút hub đang hiện ⇒ tâm nút (nép mép thì nằm trên mép); không thấy hub ⇒ giữa mép phải.
    private static func hubTargetFrame() -> CGRect {
        let size = hubTargetSize
        let center: CGPoint
        if let button = FloatingHubWindowManager.shared.visibleButtonFrame {
            center = CGPoint(x: button.midX, y: button.midY)
        } else {
            let bounds = VideoMiniPlayerWindowManager.screenMetrics().bounds
            center = CGPoint(x: bounds.maxX - size.width / 2, y: bounds.midY)
        }
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}
