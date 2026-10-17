import SwiftUI

/// Lớp điều khiển phủ trên khung phim: thanh trên, cụm giữa (lùi 10 giây · phát/dừng · tới 10 giây), thanh dưới.
///
/// - Khoá cảm ứng: chỉ còn nút mở khoá (hiện khi chạm, tự ẩn như điều khiển thường).
/// - Đang nạp / lỗi / nhúng: luôn hiện thanh trên (thu nhỏ, đóng, server…) vì lớp trạng thái phía dưới chặn chạm;
///   cụm giữa và thanh dưới chỉ có khi có item phát native.
/// - Nền chuyển màu chỉ để đọc chữ, không nhận chạm — vùng trống rơi xuống `VideoGestureLayer`.
/// - Tự ẩn chỉ làm trong suốt + tắt nhận chạm, **không** gỡ khỏi cây view: `Menu` (tốc độ, server, `⋯`) đang mở mà
///   neo của nó bị gỡ thì menu mất neo.
struct VideoPlayerControlsOverlay: View {
    let session: VideoPlaybackSession
    let controller: VideoPlayerController
    let isLandscape: Bool
    let isFullscreen: Bool
    let onMinimize: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            if controller.isTouchLocked {
                revealed(unlockButton, when: controller.controlsVisible)
            } else {
                revealed(controls, when: controller.controlsVisible || !session.hasPlayableItem)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controller.controlsVisible)
        .animation(.easeInOut(duration: 0.2), value: controller.isTouchLocked)
    }

    private var controls: some View {
        ZStack {
            if session.hasPlayableItem {
                LinearGradient(
                    colors: [Color.black.opacity(0.6), Color.black.opacity(0.15), Color.black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                VideoPlayerTopBar(
                    session: session,
                    controller: controller,
                    isLandscape: isLandscape,
                    onMinimize: onMinimize,
                    onClose: onClose
                )
                Spacer(minLength: 0)
                if session.hasPlayableItem {
                    VideoPlayerBottomBar(
                        session: session,
                        controller: controller,
                        isLandscape: isLandscape,
                        isFullscreen: isFullscreen
                    )
                    .padding(.bottom, isFullscreen ? 8 : 2)
                }
            }

            if session.hasPlayableItem {
                centerControls
            }
        }
        .transition(.opacity)
    }

    private var centerControls: some View {
        HStack(spacing: isFullscreen ? 56 : 40) {
            centerButton(systemName: "gobackward.10", size: 24, label: "Lùi 10 giây") {
                session.seek(by: -10)
                controller.showControls()
            }
            ZStack {
                if session.isBuffering {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                } else {
                    centerButton(
                        systemName: session.isPlaying ? "pause.fill" : "play.fill",
                        size: 34,
                        label: session.isPlaying ? "Tạm dừng" : "Phát"
                    ) {
                        session.togglePlayPause()
                        controller.showControls()
                    }
                }
            }
            .frame(width: 64, height: 64)
            centerButton(systemName: "goforward.10", size: 24, label: "Tới 10 giây") {
                session.seek(by: 10)
                controller.showControls()
            }
        }
    }

    private func centerButton(systemName: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func revealed(_ content: some View, when visible: Bool) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }

    private var unlockButton: some View {
        VStack {
            Spacer()
            Button {
                controller.setTouchLocked(false)
            } label: {
                Image(systemName: "lock.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.black.opacity(0.6)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mở khoá cảm ứng")
            .padding(.bottom, isFullscreen ? 28 : 12)
        }
        .transition(.opacity)
    }
}
