import SwiftUI

/// Thanh dưới của trình phát: hàng thời gian (đang xem · thanh tua có phần đã đệm · còn lại) và hàng nút biểu tượng
/// (khoá cảm ứng · tắt/bật tiếng · tập kế · danh sách tập · Xoay · toàn màn ở màn dọc).
///
/// Hàng thời gian tách thành `VideoTimelineRow` để chỉ nó vẽ lại theo tick 0,5 giây.
struct VideoPlayerBottomBar: View {
    let session: VideoPlaybackSession
    let controller: VideoPlayerController
    let isLandscape: Bool
    let isFullscreen: Bool

    var body: some View {
        VStack(spacing: 2) {
            VideoTimelineRow(session: session, controller: controller)
            HStack(spacing: 6) {
                VideoPlayerIconButton(systemName: "lock", label: "Khoá cảm ứng") {
                    controller.setTouchLocked(true)
                }
                VideoPlayerIconButton(
                    systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    label: session.isMuted ? "Bật tiếng" : "Tắt tiếng",
                    isActive: session.isMuted
                ) {
                    session.setMuted(!session.isMuted)
                    controller.showControls()
                }
                Spacer(minLength: 0)
                if session.nextEpisode != nil {
                    VideoPlayerIconButton(systemName: "forward.end.fill", label: "Tập kế") {
                        session.playNextEpisode()
                        controller.showControls()
                    }
                }
                if isFullscreen, session.episodes.contains(where: { !$0.isSection }) {
                    VideoPlayerIconButton(systemName: "list.bullet", label: "Danh sách tập") {
                        controller.setEpisodePanelVisible(true)
                    }
                }
                VideoPlayerIconButton(
                    systemName: isLandscape ? "rectangle.portrait.rotate" : "rectangle.landscape.rotate",
                    label: isLandscape ? "Xoay dọc" : "Xoay ngang"
                ) {
                    controller.rotate(currentlyLandscape: isLandscape)
                }
                if !isLandscape {
                    VideoPlayerIconButton(
                        systemName: controller.isPortraitFullscreen
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right",
                        label: controller.isPortraitFullscreen ? "Thoát toàn màn" : "Toàn màn"
                    ) {
                        controller.togglePortraitFullscreen()
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }
}
