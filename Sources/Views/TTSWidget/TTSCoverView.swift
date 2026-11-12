import SwiftUI

/// Bìa truyện tròn có hiệu ứng xoay đĩa than (Core Animation, xem `TTSRotatingCoverView`) — mặt đĩa TTS (`MediaDiscTTSFace`)
/// và đầu sheet điều khiển nhanh (`TTSQuickControlSheet`). Dời khỏi file widget "Đĩa nổi" khi kiểu đó bị bỏ (1.3.859).
struct TTSCoverView: View {
    let image: UIImage?
    let size: CGFloat
    let rotationState: CoverRotationState
    let isRotating: Bool

    var body: some View {
        TTSRotatingCoverView(
            image: image,
            size: size,
            rotationState: rotationState,
            isRotating: isRotating
        )
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
        .contentShape(Rectangle())
    }
}
