import SwiftUI
import SwiftData

/// Màn xem phim cho tiện ích loại `video`. Mọi lối vào hiện dùng màn xem (`init(watch:onDismiss:)`):
/// - Router (`BookContentDestination` → `VideoWatchRouteView`, trong `fullScreenCover` + `NavigationStack`): đóng bằng
///   `dismiss`. `init(launch:)` (mở thẳng phiên phát) giữ lại nhưng không còn chỗ gọi.
/// - Presenter cũ (`VideoPlayerPresenter`): `init(onDismiss:)` chỉ còn làm dự phòng khi phiên thiếu `modelContainer`.
/// - Màn xem (`VideoWatchPresenter` — item danh sách, mở lại từ hub / PiP): `init(watch:onDismiss:)` — `VideoWatchModel`
///   tải chi tiết + mục lục rồi tự phát theo công tắc. Phiên phát **chưa** chạy phim của màn (đang tải, tắt tự phát, phim
///   khác chạy nền) ⇒ khung phim là bìa + ▶ (`VideoWatchPosterView`) và màn **không** gắn vào phiên: phim khác vẫn chạy
///   nền, hub vẫn hiện nó, ⌄/✕ chỉ đóng màn. Phiên chuyển sang phim của màn thì mới gắn (`onChange(of: watchOwnsSession)`).
///   Phần dưới khung phim là `VideoWatchDetailsView`.
///
/// Màn hình chỉ gắn / gỡ session: biến mất mà chưa bấm Đóng ⇒ thu nhỏ (phim chạy nền, hub hiện mục Video).
/// Bố cục: màn dọc = khung 16:9 + phần dưới (màn xem: `VideoWatchDetailsView`; lối cũ: `VideoPlayerDetailsView`); ngang
/// hoặc "toàn màn" ở màn dọc = khung phim phủ cả màn. Toàn màn / khoá cảm ứng thì ẩn mọi widget nổi
/// (`FloatingWidgetSuppression`). Lối rời màn của màn xem (`VideoWatchExit`) mở trang tiếp theo **sau khi** màn đã đóng
/// (`onDisappear`): trình bày lúc màn còn đang đóng dở sẽ bị UIKit bỏ qua.
struct VideoPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private let launch: BookContentLaunch?
    private let onDismiss: (() -> Void)?
    @State private var controller: VideoPlayerController
    @State private var watch: VideoWatchModel? = nil
    @State private var isLeaving = false
    /// Việc chạy sau khi màn đã đóng hẳn (mở danh sách thể loại, Chi tiết, chuyển tab Khám phá…) — `leave(then:)`.
    @State private var pendingExitAction: (() -> Void)? = nil
    /// "Mở link lỗi" của lỗi tải chi tiết phim (màn xem) — thử lại bằng `VideoWatchModel`, không đụng phiên phát.
    @State private var openingDetailErrorLink: SourceErrorLink? = nil
    /// Trình duyệt "Mở link lỗi" (`fullScreenCover`) đã che màn lúc `onDisappear` ⇒ lần `onAppear` kế tiếp là quay lại từ
    /// trình duyệt, không phải mở màn — bỏ qua cả hai (xem chú thích ở `onDisappear`).
    @State private var isCoveredByErrorBrowser = false

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

    /// Đường màn xem: như presenter, đóng bằng closure của `VideoWatchPresenter`; `nil` (router, trong `fullScreenCover`)
    /// ⇒ `@Environment(\.dismiss)`.
    init(watch: VideoWatchModel, onDismiss: (() -> Void)? = nil) {
        self.launch = nil
        self.onDismiss = onDismiss
        _controller = State(initialValue: VideoPlayerController(session: VideoPlaybackSession.shared))
        _watch = State(initialValue: watch)
    }

    private var session: VideoPlaybackSession { controller.session }
    /// iPhone: chiều dọc compact ⇔ đang ngang.
    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var isFullscreen: Bool { isLandscape || controller.isPortraitFullscreen }
    private var suppressesFloatingWidgets: Bool { isFullscreen || controller.isTouchLocked }
    /// Màn thường (router / presenter) luôn sở hữu phiên; màn xem chỉ khi phiên đang chạy đúng phim của nó.
    private var watchOwnsSession: Bool { watch?.ownsSession ?? true }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Group {
                    if let watch, !watchOwnsSession {
                        VideoWatchPosterView(
                            model: watch,
                            onMinimize: { leave(stopPlayback: false) },
                            onClose: { leave(stopPlayback: true) },
                            onOpenErrorLink: { controller.openingErrorLink = $0 }
                        )
                    } else {
                        VideoPlayerStage(
                            session: session,
                            controller: controller,
                            isLandscape: isLandscape,
                            isFullscreen: isFullscreen,
                            onMinimize: { leave(stopPlayback: false) },
                            onClose: { leave(stopPlayback: true) }
                        )
                    }
                }
                .frame(height: isFullscreen ? geometry.size.height : geometry.size.width * 9 / 16)

                if !isFullscreen {
                    if let watch {
                        VideoWatchDetailsView(
                            model: watch,
                            session: session,
                            openingDetailErrorLink: $openingDetailErrorLink,
                            onExit: handleExit
                        )
                    } else {
                        VideoPlayerDetailsView(session: session)
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(isFullscreen)
        .persistentSystemOverlays(isFullscreen ? .hidden : .automatic)
        .animation(.easeInOut(duration: 0.25), value: isFullscreen)
        .sheet(isPresented: $controller.showsBatchDownloadSheet) {
            batchDownloadSheet
        }
        // Lớp phủ lỗi ⇒ "Mở link lỗi": đóng trình duyệt ⇒ chép cookie ⇒ đúng hành động "Thử lại" của lớp phủ.
        // Màn xem chưa phát (bìa): link lỗi là của mục lục ⇒ thử lại bằng `VideoWatchModel`, không phải phiên phát.
        .errorLinkBrowser(link: $controller.openingErrorLink, packageId: errorLinkPackageId) { retryAfterErrorLink() }
        .errorLinkBrowser(link: $openingDetailErrorLink, packageId: watch?.request.packageId) { watch?.retry() }
        .onAppear {
            if isCoveredByErrorBrowser {
                isCoveredByErrorBrowser = false
                return
            }
            VideoPlayerPresenter.install()
            if let launch {
                session.open(launch, modelContainer: modelContext.container)
            }
            if watchOwnsSession {
                session.attachScreen(controller)
            }
            watch?.start()
            // Màn xem của router (trong cover): hub mở lại phim đang chạy thì đổi chính màn này, không chồng màn mới.
            if onDismiss == nil, let watch {
                VideoWatchPresenter.noteCoverScreen(watch, isVisible: true)
            }
            controller.onMinimizeRequest = { minimizeBySwipe() }
            controller.showControls()
            FloatingWidgetSuppression.shared.isSuppressed = suppressesFloatingWidgets
            // Độ sáng lần vuốt chỉnh gần nhất (mọi phim, mọi nguồn); rời màn thì trả độ sáng của máy.
            VideoBrightnessKeeper.shared.activate(controller)
            // Nút âm lượng cứng: hiện thanh âm lượng sẵn có (thanh của iOS bị `MPVolumeView` của khung phim ẩn đi) và bỏ
            // tắt tiếng khi TTS không đọc. Màn xem chưa phát phim của nó (bìa) thì bỏ qua.
            VideoVolumeObserver.shared.activate(controller) { [controller] level in
                guard watchOwnsSession else { return }
                controller.showFeedback(.volume(level), duration: 0.8)
                controller.session.handleHardwareVolumeChange()
            }
        }
        .onChange(of: suppressesFloatingWidgets) { _, suppressed in
            FloatingWidgetSuppression.shared.isSuppressed = suppressed
        }
        .onChange(of: watchOwnsSession) { _, owns in
            guard !isLeaving else { return }
            if owns {
                session.attachScreen(controller)
                controller.showControls()
            } else {
                // Phiên rời phim của màn (dừng / đổi phim) ⇒ trả về bìa với tiến độ mới.
                session.detachScreen(controller)
                watch?.refreshResumePoint()
            }
        }
        .onChange(of: session.pictureInPictureStartCount) { _, _ in
            // Bấm PiP lúc app đang mở ⇒ thu nhỏ trình phát về màn trước, phim chạy tiếp trong cửa sổ PiP (khôi phục từ PiP
            // mở lại màn qua `requestScreen`). Đợi `didStart` mới rời màn: gỡ layer lúc PiP đang bật dở có thể làm hỏng PiP.
            // PiP tự bật khi rời app thì app không còn `.active` ⇒ giữ nguyên màn.
            guard session.isPictureInPictureActive, UIApplication.shared.applicationState == .active else { return }
            AppLogger.shared.log("🖼️ [VideoPiP] Bấm PiP khi đang mở app ⇒ thu nhỏ trình phát")
            leave(stopPlayback: false)
        }
        .onDisappear {
            // Trình duyệt "Mở link lỗi" che màn (không phải rời màn): gỡ màn lúc này sẽ thu nhỏ trình phát (hub hiện mục
            // Video) và trả khoá xoay; khi quay lại, `open` lại tự `retry()` trước khi kịp chép cookie. Giữ nguyên hết.
            if controller.openingErrorLink != nil || openingDetailErrorLink != nil {
                isCoveredByErrorBrowser = true
                return
            }
            controller.cancelTimers()
            controller.onMinimizeRequest = nil
            FloatingWidgetSuppression.shared.isSuppressed = false
            VideoOrientationLock.resetForExit()
            // `resetForExit` vừa bỏ khoá ⇒ đồng bộ nút khoá xoay nếu màn này hiện lại.
            controller.isOrientationLocked = false
            session.detachScreen(controller)
            VideoBrightnessKeeper.shared.deactivate(controller)
            VideoVolumeObserver.shared.deactivate(controller)
            // Màn xem bị đóng bằng code (presenter mở phim khác, về tab…) không qua `leave` ⇒ huỷ lượt tải ở đây, kẻo tải
            // xong muộn lại tự mở phim khi không còn màn.
            watch?.cancel()
            if let watch {
                VideoWatchPresenter.noteCoverScreen(watch, isVisible: false)
            }
            // Màn đã đóng hẳn ⇒ mới mở trang tiếp theo của lối rời màn (một nhịp main sau, khi UIKit xong chuyển cảnh).
            if let action = pendingExitAction {
                pendingExitAction = nil
                DispatchQueue.main.async { action() }
            }
        }
    }

    /// "Tải nhiều tập…" của menu `⋯`: sheet tải chung (`TaskOptionsSheet` tự sang chế độ video theo nguồn).
    @ViewBuilder
    private var batchDownloadSheet: some View {
        if let book = session.fetchBook() {
            TaskOptionsSheet(book: book, taskType: .download)
        } else {
            Text("Phim chưa có trong thư viện nên chưa tải được.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
                .presentationDetents([.fraction(0.2)])
        }
    }

    // MARK: - Rời màn

    /// Thu nhỏ (`stopPlayback == false`): phim chạy nền, `onDisappear` gỡ màn khỏi session. Đóng: dừng hẳn trước.
    /// Đang ngang thì trả về dọc rồi mới đóng màn để phần còn lại của app không nằm ngang. `then` chạy sau khi màn đã đóng.
    private func leave(stopPlayback: Bool, then action: (() -> Void)? = nil) {
        guard !isLeaving else { return }
        isLeaving = true
        pendingExitAction = action
        // Màn xem chưa phát phim của nó: ✕ chỉ đóng màn, không dừng phim khác đang chạy nền.
        if stopPlayback, watchOwnsSession {
            session.stop()
        }
        watch?.cancel()
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

    /// Vuốt xuống khung phim (chỉ màn dọc): hub hoặc PiP theo `VideoMinimizePolicy` (nút ⌄ luôn hub). PiP được thì chỉ
    /// **bật PiP**: handler `pictureInPictureStartCount` tự thu nhỏ khi PiP đã bật — đóng màn trước là gỡ layer lúc PiP
    /// đang bật dở. PiP không lên sau 1,5 giây (bị từ chối, lỗi) ⇒ thu nhỏ vào hub như cũ.
    private func minimizeBySwipe() {
        guard !isLeaving, watchOwnsSession, let playing = session.launch,
              VideoMinimizePolicy.style(bookId: playing.bookId, packageId: playing.extensionPackageId) == .pictureInPicture
        else {
            leave(stopPlayback: false)
            return
        }
        guard session.isPictureInPicturePossible, !session.isPictureInPictureActive else {
            AppLogger.shared.log("🖼️ [VideoPiP] Vuốt xuống: chưa bật được PiP (phim nhúng / chưa sẵn sàng) ⇒ thu nhỏ vào hub")
            leave(stopPlayback: false)
            return
        }
        AppLogger.shared.log("🖼️ [VideoPiP] Vuốt xuống ⇒ bật Hình trong hình theo cài đặt")
        session.togglePictureInPicture()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !isLeaving, !session.isPictureInPictureActive else { return }
            AppLogger.shared.log("🖼️ [VideoPiP] PiP không lên sau khi vuốt xuống ⇒ thu nhỏ vào hub")
            leave(stopPlayback: false)
        }
    }

    // MARK: - Màn xem chưa phát

    private var errorLinkPackageId: String? {
        if let watch, !watchOwnsSession { return watch.request.packageId }
        return session.launch?.extensionPackageId
    }

    private func retryAfterErrorLink() {
        if let watch, !watchOwnsSession {
            watch.retry()
        } else {
            session.retry()
        }
    }

    // MARK: - Lối rời màn xem

    /// Thu nhỏ phim (Home với phim 18+ thì `prepareGoHome` đã dừng hẳn) rồi, khi màn đã đóng, mở trang tiếp theo. Trang
    /// tiếp theo là sheet lớn của `VideoWatchPresenter` (màn xem không nằm trong `NavigationStack` của tab nào).
    private func handleExit(_ exit: VideoWatchExit) {
        guard let watch else { return }
        let container = modelContext.container
        let packageId = watch.request.packageId
        let sourceName = watch.request.sourceName
        switch exit {
        case .genre(let genre):
            let ext = ExtensionLibraryRepository.shared.catalogExtension(packageId: packageId)
            AppLogger.shared.log("🎬 [VideoWatch] Mở thể loại '\(genre.title)' từ màn xem ⇒ thu nhỏ phim")
            leave(stopPlayback: false) {
                VideoWatchPresenter.presentPage(modelContainer: container) {
                    CategoryNovelsListView(
                        category: genre,
                        extensionPackageId: packageId,
                        localPath: ext?.localPath ?? "",
                        downloadUrl: ext?.downloadUrl ?? "",
                        configJson: ext?.configJson ?? "{}",
                        sourceName: sourceName
                    )
                }
            }
        case .openDetail(let request):
            leave(stopPlayback: false) {
                VideoWatchPresenter.presentPage(modelContainer: container) {
                    BookDetailView(
                        bookId: request.detailUrl,
                        extensionPackageId: request.packageId,
                        initialDetailUrl: request.detailUrl,
                        sourceName: request.sourceName,
                        initialHost: request.host
                    )
                }
            }
        case .home:
            watch.prepareGoHome()
            leave(stopPlayback: false) {
                VideoWatchPresenter.dismissPage {
                    MainTabNavigationEvents.shared.send(.showDiscoveryRoot)
                }
            }
        case .close:
            leave(stopPlayback: true)
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
