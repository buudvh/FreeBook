import SwiftUI
import SwiftData

/// Màn xem phim cho tiện ích loại `video`. Hai đường vào:
/// - Router (`BookContentDestination`, trong `fullScreenCover` + `NavigationStack`): `init(launch:)` mở phim vào
///   `VideoPlaybackSession` (cùng phim đang chạy nền thì chỉ gắn lại).
/// - Presenter (`VideoPlayerPresenter`, mở lại từ hub / PiP): `init(onDismiss:)` gắn vào phiên đang chạy.
///
/// Màn hình chỉ gắn / gỡ session: biến mất mà chưa bấm Đóng ⇒ thu nhỏ (phim chạy nền, hub hiện mục Video).
/// Bố cục: màn dọc = khung 16:9 + tên phim, chip server, lưới tập; ngang hoặc "toàn màn" ở màn dọc = khung phim phủ
/// cả màn. Toàn màn / khoá cảm ứng thì ẩn mọi widget nổi (`FloatingWidgetSuppression`).
struct VideoPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private let launch: BookContentLaunch?
    private let onDismiss: (() -> Void)?
    @State private var controller: VideoPlayerController
    @State private var isLeaving = false

    init(launch: BookContentLaunch) {
        self.launch = launch
        self.onDismiss = nil
        _controller = State(initialValue: VideoPlayerController(session: VideoPlaybackSession.shared))
    }

    /// Đường presenter: không dùng `@Environment(\.dismiss)` (không đáng tin trong `UIHostingController` trình bày bằng
    /// UIKit) mà gọi closure của presenter.
    init(onDismiss: @escaping () -> Void) {
        self.launch = nil
        self.onDismiss = onDismiss
        _controller = State(initialValue: VideoPlayerController(session: VideoPlaybackSession.shared))
    }

    private var session: VideoPlaybackSession { controller.session }
    /// iPhone: chiều dọc compact ⇔ đang ngang.
    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var isFullscreen: Bool { isLandscape || controller.isPortraitFullscreen }
    private var suppressesFloatingWidgets: Bool { isFullscreen || controller.isTouchLocked }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                VideoPlayerStage(
                    session: session,
                    controller: controller,
                    isLandscape: isLandscape,
                    isFullscreen: isFullscreen,
                    onMinimize: { leave(stopPlayback: false) },
                    onClose: { leave(stopPlayback: true) }
                )
                .frame(height: isFullscreen ? geometry.size.height : geometry.size.width * 9 / 16)

                if !isFullscreen {
                    VideoPlayerDetailsView(session: session)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(isFullscreen)
        .persistentSystemOverlays(isFullscreen ? .hidden : .automatic)
        .animation(.easeInOut(duration: 0.25), value: isFullscreen)
        .onAppear {
            VideoPlayerPresenter.install()
            if let launch {
                session.open(launch, modelContainer: modelContext.container)
            }
            session.attachScreen()
            controller.onMinimizeRequest = { leave(stopPlayback: false) }
            controller.showControls()
            FloatingWidgetSuppression.shared.isSuppressed = suppressesFloatingWidgets
        }
        .onChange(of: suppressesFloatingWidgets) { _, suppressed in
            FloatingWidgetSuppression.shared.isSuppressed = suppressed
        }
        .onDisappear {
            controller.cancelTimers()
            controller.onMinimizeRequest = nil
            FloatingWidgetSuppression.shared.isSuppressed = false
            VideoOrientationLock.resetForExit()
            session.detachScreen()
        }
    }

    // MARK: - Rời màn

    /// Thu nhỏ (`stopPlayback == false`): phim chạy nền, `onDisappear` gỡ màn khỏi session. Đóng: dừng hẳn trước.
    /// Đang ngang thì trả về dọc rồi mới đóng màn để phần còn lại của app không nằm ngang.
    private func leave(stopPlayback: Bool) {
        guard !isLeaving else { return }
        isLeaving = true
        if stopPlayback {
            session.stop()
        }
        controller.cancelTimers()
        FloatingWidgetSuppression.shared.isSuppressed = false
        let wasLandscape = isLandscape
        VideoOrientationLock.resetForExit()
        if wasLandscape {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                performDismiss()
            }
        } else {
            performDismiss()
        }
    }

    private func performDismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }
}
