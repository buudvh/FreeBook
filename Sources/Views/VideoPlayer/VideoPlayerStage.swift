import SwiftUI

/// Khung phim (dọc 16:9 hoặc toàn màn), xếp lớp từ dưới lên:
/// hình (`VideoPlayerSurfaceView`) hoặc trang nhúng → phụ đề → cử chỉ → trạng thái nạp/lỗi → điều khiển → nút
/// "Bỏ qua" → HUD cử chỉ → bảng danh sách tập (toàn màn).
///
/// Trang nhúng cần chạm trực tiếp nên khi nhúng không có lớp cử chỉ, chỉ còn thanh trên.
/// Toàn màn: hình, nền và lớp cử chỉ tràn qua vùng an toàn (tai thỏ, home indicator); điều khiển vẫn nằm trong vùng an
/// toàn để không bị che. Hình không tràn khỏi khung nhờ container của `VideoPlayerSurfaceView` tự `clipsToBounds`.
struct VideoPlayerStage: View {
    let session: VideoPlaybackSession
    let controller: VideoPlayerController
    let isLandscape: Bool
    let isFullscreen: Bool
    let onMinimize: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(.all, edges: bleedEdges)

            if let embed = session.embedContent {
                VideoEmbedWebView(content: embed)
                    .padding(.top, 44)
            } else {
                VideoPlayerSurfaceView(layerView: session.layerView, gravity: controller.gravity.layerGravity)
                    .ignoresSafeArea(.all, edges: bleedEdges)
                if session.isPictureInPictureActive {
                    pictureInPicturePlaceholder
                }
                VideoSubtitleOverlay(session: session, liftsAboveControls: controller.controlsVisible && !controller.isTouchLocked)
                VideoGestureLayer(
                    verticalMode: isFullscreen ? .levels : .dismiss,
                    isTouchLocked: controller.isTouchLocked,
                    handlers: gestureHandlers
                )
                .ignoresSafeArea(.all, edges: bleedEdges)
            }

            VideoPlayerStatusView(
                phase: session.phase,
                canTryAnotherServer: session.canTryAnotherServer,
                onRetry: { session.retry() },
                onTryAnotherServer: { session.tryAnotherServer() }
            )

            VideoPlayerControlsOverlay(
                session: session,
                controller: controller,
                isLandscape: isLandscape,
                isFullscreen: isFullscreen,
                onMinimize: onMinimize,
                onClose: onClose
            )

            if !controller.isTouchLocked {
                VideoSkipSegmentButton(session: session, isFullscreen: isFullscreen)
            }

            VideoPlayerGestureHUD(feedback: controller.feedback)

            if controller.showsEpisodePanel, isFullscreen {
                VideoEpisodePanel(session: session) {
                    controller.setEpisodePanelVisible(false)
                }
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controller.showsEpisodePanel)
    }

    private var bleedEdges: Edge.Set { isFullscreen ? .all : [] }

    private var pictureInPicturePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "pip")
                .font(.system(size: 28, weight: .semibold))
            Text("Đang phát trong cửa sổ hình trong hình")
                .font(.footnote)
        }
        .foregroundStyle(.white.opacity(0.7))
        .allowsHitTesting(false)
    }

    private var gestureHandlers: VideoGestureView.Handlers {
        let owner = self.controller
        var handlers = VideoGestureView.Handlers()
        handlers.singleTap = { owner.handleSingleTap(side: $0) }
        handlers.doubleTap = { owner.handleDoubleTap(side: $0) }
        handlers.panBegan = { owner.handlePanBegan($0) }
        handlers.panChanged = { owner.handlePanChanged($0, value: $1) }
        handlers.panEnded = { owner.handlePanEnded($0, value: $1) }
        handlers.longPress = { owner.handleLongPress($0) }
        return handlers
    }
}
