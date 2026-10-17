import SwiftUI

/// Vùng player 16:9: `AVPlayerContainerView` hoặc trang nhúng, cộng nút "Bỏ qua" nổi và lớp trạng thái.
///
/// Tách khỏi `VideoPlayerScreen` để chỉ view này đọc `currentCueText` / `skipTargetSeconds`
/// (đổi theo tick 0,5 giây) — phần còn lại của màn không vẽ lại theo từng tick.
struct VideoPlayerSurface: View {
    let controller: VideoPlayerController

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black

            if let embed = controller.embedContent {
                VideoEmbedWebView(content: embed)
            } else {
                AVPlayerContainerView(
                    player: controller.player,
                    subtitleText: controller.subtitlesEnabled ? controller.currentCueText : "",
                    onFullScreenChange: { [controller] isFullScreen in
                        controller.setSystemFullScreen(isFullScreen)
                    }
                )
            }

            if controller.skipTargetSeconds != nil, controller.embedContent == nil {
                skipButton
            }

            VideoPlayerStatusView(
                phase: controller.phase,
                canTryAnotherServer: controller.canTryAnotherServer,
                onRetry: { controller.retry() },
                onTryAnotherServer: { controller.tryAnotherServer() }
            )
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var skipButton: some View {
        Button {
            controller.skipCurrentSegment()
        } label: {
            Label("Bỏ qua", systemImage: "forward.end.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(Capsule().fill(Color.black.opacity(0.7)))
                .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        // Đặt trên thanh điều khiển của AVKit để không che nút tua.
        .padding(.trailing, 12)
        .padding(.bottom, 56)
    }
}
