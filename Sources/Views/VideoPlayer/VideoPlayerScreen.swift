import SwiftUI
import SwiftData

/// Màn xem phim cho tiện ích loại `video`. Mọi lối vào hiện dùng màn xem (`init(watch:onDismiss:)`):
/// - Router (`BookContentDestination` → `VideoWatchRouteView`, trong `fullScreenCover` + `NavigationStack`): đóng bằng
///   `dismiss`. `init(launch:)` (mở thẳng phiên phát) giữ lại nhưng không còn chỗ gọi.
/// - Presenter cũ (`VideoPlayerPresenter`): `init(onDismiss:)` chỉ còn làm dự phòng khi phiên thiếu `modelContainer`.
/// - Màn xem (`VideoWatchPresenter` — item danh sách, mở lại từ hub / cửa sổ nhỏ): `init(watch:onDismiss:)` — `VideoWatchModel`
///   tải chi tiết + mục lục rồi tự phát theo công tắc. Phiên phát **chưa** chạy phim của màn (đang tải, tắt tự phát, phim
///   khác chạy nền) ⇒ khung phim là bìa + ▶ (`VideoWatchPosterView`) và màn **không** gắn vào phiên: phim khác vẫn chạy
///   nền, hub vẫn hiện nó, ⌄/✕ chỉ đóng màn. Phiên chuyển sang phim của màn thì mới gắn (`onChange(of: watchOwnsSession)`).
///   Phần dưới khung phim là `VideoWatchDetailsView`.
///
/// Màn hình chỉ gắn / gỡ session: biến mất mà chưa bấm Đóng ⇒ thu nhỏ (phim chạy nền, hub hiện mục Video).
/// Thu nhỏ (1.3.751, `VideoMinimizeDragContainer` + `VideoMinimizeAnimator`): vuốt xuống khung phim ở màn dọc ⇒ khung phim
/// co theo tay, lộ dần màn phía sau; nhả tay ⇒ theo `VideoMinimizePolicy`: bay vào nút hub, hoặc thành cửa sổ nhỏ trong app
/// (`VideoMiniPlayerWindowManager`). Nút ⌄ luôn bay vào hub; nút "Cửa sổ nhỏ" của thanh trên luôn ra cửa sổ nhỏ. Tới đích
/// rồi màn mới đóng, **không** animation. Presenter để nền trong suốt, router dùng `presentationBackground(.clear)`.
/// Bố cục: màn dọc = khung 16:9 + phần dưới (màn xem: `VideoWatchDetailsView`; lối cũ: `VideoPlayerDetailsView`); ngang
/// hoặc "toàn màn" ở màn dọc = khung phim phủ cả màn. Toàn màn / khoá cảm ứng thì ẩn mọi widget nổi
/// (`FloatingWidgetSuppression`). Lối rời màn của màn xem (`VideoWatchExit`: Home, đổi nguồn, thể loại / Xem thêm — xử lý
/// ở `+Exit`) làm việc tiếp theo **sau khi** màn đã đóng (`onDisappear`): trình bày lúc màn còn đang đóng dở sẽ bị UIKit
/// bỏ qua. Thể loại / Xem thêm lúc màn đang phát phim của nó ⇒ phim vào cửa sổ nhỏ, màn đóng rồi mới mở trang danh sách;
/// màn hiện bìa / phim nhúng trang ⇒ trang đè lên màn. Chi tiết của đề xuất không phải phim mở trang đè lên màn
/// (`VideoWatchPagePresenter`), màn vẫn gắn, phim vẫn phát.
struct VideoPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private let launch: BookContentLaunch?
    /// Tham số = có animation khi đóng (thu nhỏ có hiệu ứng riêng thì đóng không animation).
    private let onDismiss: ((Bool) -> Void)?
    @State var controller: VideoPlayerController
    @State var watch: VideoWatchModel? = nil
    @State var isLeaving = false
    /// Việc chạy sau khi màn đã đóng hẳn (chuyển tab Khám phá…) — `leave(then:)`.
    @State private var pendingExitAction: (() -> Void)? = nil
    /// "Mở link lỗi" của lỗi tải chi tiết phim (màn xem) — thử lại bằng `VideoWatchModel`, không đụng phiên phát.
    @State var openingDetailErrorLink: SourceErrorLink? = nil
    /// Nút "Trình duyệt" của hàng nút màn xem (1.3.763): trang chi tiết của phim, đóng lại chỉ chép cookie, không thử lại.
    @State var openingDetailPage: SourceErrorLink? = nil
    /// Trình duyệt "Mở link lỗi" / "Trình duyệt" (`fullScreenCover`) đã che màn lúc `onDisappear` ⇒ lần `onAppear` kế tiếp
    /// là quay lại từ trình duyệt, không phải mở màn — bỏ qua cả hai (xem chú thích ở `onDisappear`).
    @State private var isCoveredByErrorBrowser = false

    init(launch: BookContentLaunch) {
        self.launch = launch
        self.onDismiss = nil
        _controller = State(initialValue: VideoPlayerController(session: VideoPlaybackSession.shared))
    }

    /// Đường presenter: không dùng `@Environment(\.dismiss)` (không đáng tin trong `UIHostingController` trình bày bằng
    /// UIKit) mà gọi closure của presenter.
    init(onDismiss: @escaping (Bool) -> Void) {
        self.launch = nil
        self.onDismiss = onDismiss
        _controller = State(initialValue: VideoPlayerController(session: VideoPlaybackSession.shared))
    }

    /// Đường màn xem: như presenter, đóng bằng closure của `VideoWatchPresenter`; `nil` (router, trong `fullScreenCover`)
    /// ⇒ `@Environment(\.dismiss)`.
    init(watch: VideoWatchModel, onDismiss: ((Bool) -> Void)? = nil) {
        self.launch = nil
        self.onDismiss = onDismiss
        _controller = State(initialValue: VideoPlayerController(session: VideoPlaybackSession.shared))
        _watch = State(initialValue: watch)
    }

    var session: VideoPlaybackSession { controller.session }
    /// iPhone: chiều dọc compact ⇔ đang ngang.
    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var isFullscreen: Bool { isLandscape || controller.isPortraitFullscreen }
    private var suppressesFloatingWidgets: Bool { isFullscreen || controller.isTouchLocked }
    /// Màn thường (router / presenter) luôn sở hữu phiên; màn xem chỉ khi phiên đang chạy đúng phim của nó.
    var watchOwnsSession: Bool { watch?.ownsSession ?? true }

    var body: some View {
        // Khung phim co theo tay khi thu nhỏ (1.3.751) — chỉ container vẽ lại theo nhịp kéo.
        VideoMinimizeDragContainer(drag: controller.minimizeDrag, isFullscreen: isFullscreen) {
            videoArea
        } details: {
            detailsArea
        }
        .preferredColorScheme(.dark)
        // Màn xem phim đang ở trên cùng ⇒ ẩn đĩa nghe góc dưới phải (1.3.808); trang đè lên màn xem thì đĩa hiện lại.
        .mediaDiscAnchor(.blocker)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(isFullscreen)
        .persistentSystemOverlays(isFullscreen ? .hidden : .automatic)
        .animation(.easeInOut(duration: 0.25), value: isFullscreen)
        .sheet(isPresented: $controller.showsBatchDownloadSheet) {
            Group {
                batchDownloadSheet
            }
            .appGlassSheet()
        }
        .sheet(isPresented: $controller.showsSleepTimerSheet) {
            Group {
                MediaSleepTimerSheet(timer: session.sleepTimer)
            }
            .appGlassSheet()
        }
        .sheet(isPresented: $controller.showsCaptionTranslationSheet) {
            Group {
                if let launch = session.launch {
                    MediaCaptionTranslationSheet(
                        medium: .video, bookId: launch.bookId, packageId: launch.extensionPackageId,
                        sourceName: launch.bookSourceName ?? ""
                    ) { session.retranslateSubtitles() }
                }
            }
            .appGlassSheet()
        }
        .modifier(VideoBookDictionarySheetModifier(isPresented: $controller.showsBookDictionarySheet, session: session))
        .sheet(item: $controller.playlistAddRequest) { presentedItem in PlaylistAddSheet(request: presentedItem).appGlassSheet() }
        // Lớp phủ lỗi ⇒ "Mở link lỗi": đóng trình duyệt ⇒ chép cookie ⇒ đúng hành động "Thử lại" của lớp phủ.
        // Màn xem chưa phát (bìa): link lỗi là của mục lục ⇒ thử lại bằng `VideoWatchModel`, không phải phiên phát.
        .errorLinkBrowser(link: $controller.openingErrorLink, packageId: errorLinkPackageId) { retryAfterErrorLink() }
        .errorLinkBrowser(link: $openingDetailErrorLink, packageId: watch?.request.packageId) { watch?.retry() }
        // Nút "Trình duyệt": không lỗi nên không thử lại gì — phim đang phát giữ nguyên.
        .sourcePageBrowser(link: $openingDetailPage, packageId: watch?.request.packageId)
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
            // Hết phim lúc màn đang hiện ⇒ tự sang phim đề xuất đổi chính màn này (`VideoAutoNextCoordinator`).
            if let watch {
                VideoAutoNextCoordinator.shared.noteScreen(watch, isVisible: true)
            }
            // Màn xem của router (trong cover): hub mở lại phim đang chạy thì đổi chính màn này, không chồng màn mới.
            if onDismiss == nil, let watch {
                VideoWatchPresenter.noteCoverScreen(watch, isVisible: true)
            }
            controller.onMinimizeRelease = { translation, velocity in
                handleMinimizeRelease(translation: translation, velocity: velocity)
            }
            // Tắt NSFW lúc phát phim 18+ ⇒ thu màn vào hub (`+Exit`).
            registerHubCollapse()
            controller.showControls()
            FloatingWidgetSuppression.shared.isSuppressed = suppressesFloatingWidgets
            // Độ sáng lần vuốt chỉnh gần nhất (mọi phim, mọi nguồn); rời màn thì trả độ sáng của máy.
            VideoBrightnessKeeper.shared.activate(controller)
            // Nút âm lượng cứng: hiện thanh âm lượng sẵn có (thanh của iOS bị `MPVolumeView` của khung phim ẩn đi) và bỏ
            // tắt tiếng khi TTS không đọc. Màn xem chưa phát phim của nó (bìa) thì bỏ qua.
            VideoVolumeObserver.shared.activate(controller) { [controller] level in
                // Trang toàn màn đang che màn (thể loại, Xem thêm, Chi tiết) ⇒ màn không "đang hiện": bỏ qua.
                guard watchOwnsSession, !VideoWatchPagePresenter.isPresenting else { return }
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
        .onDisappear {
            // Trình duyệt "Mở link lỗi" / "Trình duyệt" che màn (không phải rời màn): gỡ màn lúc này sẽ thu nhỏ trình phát
            // (hub hiện mục Video) và trả khoá xoay; khi quay lại, `open` lại tự `retry()` trước khi kịp chép cookie. Giữ
            // nguyên hết.
            if controller.openingErrorLink != nil || openingDetailErrorLink != nil || openingDetailPage != nil {
                isCoveredByErrorBrowser = true
                return
            }
            controller.cancelTimers()
            controller.onMinimizeRelease = nil
            VideoLeaveToHubCoordinator.shared.unregister(controller)
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
                VideoAutoNextCoordinator.shared.noteScreen(watch, isVisible: false)
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
    /// `animated == false` khi khung phim đã tự co tới đích (hub / cửa sổ nhỏ).
    func leave(stopPlayback: Bool, animated: Bool = true, then action: (() -> Void)? = nil) {
        guard !isLeaving else { return }
        isLeaving = true
        pendingExitAction = action
        // Thu nhỏ khi đang phát ⇒ phiên giữ phát lúc màn rời đi (1.3.765, `noteMinimizing`).
        if !stopPlayback, watchOwnsSession {
            session.noteMinimizing()
        }
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
                performDismiss(animated: animated)
            }
        } else {
            performDismiss(animated: animated)
        }
    }

    // MARK: - Thu nhỏ

    /// Nhả tay của vuốt xuống khung phim (màn dọc): đủ xa / hất nhanh ⇒ theo `VideoMinimizePolicy` (cửa sổ nhỏ hoặc hub;
    /// phim nhúng trang luôn hub); chưa tới ⇒ khung phim bật về.
    private func handleMinimizeRelease(translation: CGFloat, velocity: CGFloat) {
        let drag = controller.minimizeDrag
        guard !isLeaving, watchOwnsSession, !drag.isCommitted,
              VideoMinimizeAnimator.shouldCommit(translation: translation, velocity: velocity) else {
            VideoMinimizeAnimator.springBack(drag)
            return
        }
        let style = session.launch.map {
            VideoMinimizePolicy.style(bookId: $0.bookId, packageId: $0.extensionPackageId)
        } ?? VideoMinimizePolicy.defaultValue
        if style == .miniPlayer, session.embedContent == nil {
            AppLogger.shared.log("🎬 [VideoPlayer] Vuốt xuống ⇒ cửa sổ nhỏ theo cài đặt")
            dockToMiniPlayer()
        } else {
            AppLogger.shared.log("🎬 [VideoPlayer] Vuốt xuống ⇒ thu nhỏ vào hub")
            flyToHub()
        }
    }

    /// Nút ⌄: luôn vào hub — màn dọc thì khung phim bay vào nút hub, ngang / toàn màn thì đóng như cũ. `then` chạy sau khi
    /// màn đã đóng hẳn (nút Home, `+Exit`).
    func minimizeToHub(then action: (() -> Void)? = nil) {
        guard !isLeaving, !controller.minimizeDrag.isCommitted else { return }
        guard !isFullscreen else {
            leave(stopPlayback: false, then: action)
            return
        }
        flyToHub(then: action)
    }

    /// Nút "Cửa sổ nhỏ" của thanh trên (và thể loại / Xem thêm, `+Exit`). Đang ngang / toàn màn dọc ⇒ về khung dọc trước
    /// rồi mới co. `then` chạy sau khi màn đã đóng hẳn.
    func minimizeToMiniPlayer(then action: (() -> Void)? = nil) {
        guard !isLeaving, !controller.minimizeDrag.isCommitted, session.embedContent == nil else { return }
        guard isFullscreen else {
            dockToMiniPlayer(then: action)
            return
        }
        if isLandscape {
            controller.rotate(currentlyLandscape: true)
        } else {
            controller.togglePortraitFullscreen()
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !isLeaving else { return }
            dockToMiniPlayer(then: action)
        }
    }

    private func flyToHub(then action: (() -> Void)? = nil) {
        VideoMinimizeAnimator.flyToHub(controller.minimizeDrag) {
            leave(stopPlayback: false, animated: false, then: action)
        }
    }

    private func dockToMiniPlayer(then action: (() -> Void)? = nil) {
        VideoMinimizeAnimator.dockToMiniPlayer(controller.minimizeDrag) {
            leave(stopPlayback: false, animated: false, then: action)
        }
    }

    // MARK: - Bố cục

    /// Khung phim: bìa + ▶ khi màn xem chưa phát phim của nó, còn lại là trình phát.
    @ViewBuilder
    private var videoArea: some View {
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
                onMinimize: { minimizeToHub() },
                onClose: { leave(stopPlayback: true) },
                onMiniPlayer: { minimizeToMiniPlayer() }
            )
        }
    }

    /// Phần dưới khung phim (màn dọc, không toàn màn).
    @ViewBuilder
    private var detailsArea: some View {
        if let watch {
            VideoWatchDetailsView(
                model: watch,
                session: session,
                openingDetailErrorLink: $openingDetailErrorLink,
                openingDetailPage: $openingDetailPage,
                onExit: handleExit
            )
        } else {
            VideoPlayerDetailsView(session: session)
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

    // MARK: - Đóng màn

    /// Đóng trang toàn màn đang đè lên màn (nếu có) trước: gọi đóng màn khi còn trang chỉ đóng được trang. Trang nằm dưới
    /// màn (mở sau khi màn đóng, màn mở lại từ cửa sổ nhỏ phủ lên) giữ nguyên — đóng màn là về trang đó.
    private func performDismiss(animated: Bool = true) {
        VideoWatchPagePresenter.dismissCoveringPage(animated: false) {
            if let onDismiss {
                onDismiss(animated)
            } else if animated {
                dismiss()
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { dismiss() }
            }
        }
    }
}
