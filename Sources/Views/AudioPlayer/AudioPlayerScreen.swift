import SwiftUI

/// **Màn nghe** của trình nghe âm thanh (tiện ích loại `audio`), bố cục tham khảo các app nghe nhạc phổ biến: nền tối lấy
/// màu bìa, header (⌄ · "Phát từ album" + tên album · `…`), chấm chỉ trang và **3 trang vuốt ngang** — Danh sách phát,
/// Đĩa (mở vào trang này, trừ khi chỗ gọi truyền `initialPage`), Lời bài hát.
///
/// Màn chỉ đọc `AudioPlaybackSession` (`@Observable`) và gọi hàm của nó; giây phát (tick 0,5 s) chỉ được đọc ở các view nhỏ
/// (`AudioPlayerSeekRow`) để cả màn không vẽ lại mỗi tick.
///
/// Hai lối trình bày:
/// - Presenter (`AudioPlayerPresenter`, item danh sách / mở lại từ đĩa góc dưới): `init(onDismiss:)` — đóng bằng closure
///   của presenter (UIKit `.overFullScreen`).
/// - Router (`AudioListenRouteView`, trong `fullScreenCover` + `NavigationStack` của chỗ gọi): `onDismiss == nil` ⇒
///   `@Environment(\.dismiss)`.
///
/// Gắn / gỡ màn vào session (`attachScreen` / `detachScreen`) theo `onAppear` / `onDisappear` — đĩa góc dưới ẩn khi có màn
/// gắn. Thu nhỏ (⌄ hoặc vuốt xuống ở header / đĩa / tên bài / đầu trang Danh sách, Lời) chỉ đóng màn, nhạc vẫn phát.
/// Trình duyệt "Mở link lỗi" / "Mở trang nguồn" che màn (cover) cũng gây `onDisappear` ⇒ bỏ qua lượt gỡ đó (như
/// `VideoPlayerScreen`). Session dừng hẳn lúc màn đang hiện (✕ ở đĩa góc dưới, màn khoá) ⇒ màn tự đóng.
struct AudioPlayerScreen: View {
    /// Khoá gắn màn vào session (`attachScreen` cần một đối tượng; view là struct).
    final class ScreenToken {}

    @Environment(\.dismiss) private var dismiss
    /// App đang active — đĩa chỉ xoay khi app ở trước. **Không** dùng `@Environment(\.scenePhase)`: màn này trình bày bằng
    /// UIKit (`AudioPlayerPresenter`, host riêng ngoài cây SwiftUI của scene) nên giá trị đó có thể không tới ⇒ đĩa đứng im
    /// dù đang phát. Theo dõi thẳng thông báo của `UIApplication`.
    @State private var isAppActive = UIApplication.shared.applicationState != .background

    /// Tham số = có animation khi đóng (vuốt xuống đã tự trượt màn đi thì đóng không animation).
    private let onDismiss: ((Bool) -> Void)?

    @State private var token = ScreenToken()
    @State private var drag = AudioMinimizeDragState()
    @State private var page: AudioPlayerPage
    @State private var showingMenu = false
    /// Sheet hẹn giờ tắt mở từ ngăn kéo `…` (nút ⏱ của trang Đĩa có sheet riêng — `AudioSecondaryControls`).
    @State private var showingSleepTimer = false
    /// Sheet "Thêm vào playlist" của hàng ngăn kéo (bài đang phát).
    @State private var playlistRequest: PlaylistAddRequest? = nil
    @State private var isOnShelf = false
    @State private var hasBook = false
    @State private var isLeaving = false
    @State private var openingErrorLink: SourceErrorLink? = nil
    @State private var openingSourcePage: SourceErrorLink? = nil
    /// Trình duyệt (cover) đã che màn lúc `onDisappear` ⇒ lần `onAppear` kế tiếp là quay lại từ trình duyệt.
    @State private var isCoveredByBrowser = false

    private static let slideOutDuration: Double = 0.22

    /// `initialPage`: trang mở vào — mặc định Đĩa; sheet điều khiển nhanh của Reader mở thẳng Danh sách / Lời
    /// (`AudioPlayerPresenter.reopen(at:)`).
    init(initialPage: AudioPlayerPage = .disc, onDismiss: ((Bool) -> Void)? = nil) {
        self.onDismiss = onDismiss
        _page = State(initialValue: initialPage)
    }

    private var session: AudioPlaybackSession { .shared }

    /// Host của album (item → `Book.host`) — `Referer` khi tải bìa, ghép link trang nguồn.
    private var referer: String? {
        ExtensionHostResolver.nonEmpty(session.request?.host) ?? ExtensionHostResolver.nonEmpty(session.bookHost)
    }

    var body: some View {
        AudioMinimizeDragContainer(drag: drag) {
            ZStack {
                AudioCoverBackdrop(coverUrl: session.coverUrl, referer: referer)
                VStack(spacing: 0) {
                    AudioPlayerHeader(
                        albumTitle: session.albumTitle,
                        onMinimize: { minimize(bySwipe: false) },
                        onMenu: { showingMenu = true }
                    )
                    .audioMinimizeDrag(drag) { minimize(bySwipe: true) }
                    AudioPageIndicator(selection: $page)
                    pages.overlay(alignment: .top) { AudioPlaybackNoticeBanner().padding(.top, 6) }
                }
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .sideDrawerMenu(isPresented: $showingMenu, title: "Trình nghe") {
            drawerMenu
        }
        .sheet(isPresented: $showingSleepTimer) {
            MediaSleepTimerSheet(timer: AudioPlaybackSession.shared.sleepTimer)
        }
        .sheet(item: $playlistRequest) { PlaylistAddSheet(request: $0) }
        // Bài lỗi ⇒ "Mở link lỗi": đóng trình duyệt ⇒ chép cookie ⇒ thử lại bài.
        .errorLinkBrowser(link: $openingErrorLink, packageId: session.packageId) {
            AudioPlaybackSession.shared.retry()
        }
        // "Mở trang nguồn": không lỗi nên không thử lại gì.
        .sourcePageBrowser(link: $openingSourcePage, packageId: session.packageId)
        .onAppear { handleAppear() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in isAppActive = true }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in isAppActive = false }
        .onDisappear { handleDisappear() }
        .onChange(of: session.isActive) { _, active in
            if !active { closeAfterStop() }
        }
        .onChange(of: session.bookId) { _, _ in refreshShelf() }
        .onChange(of: session.currentTrackIndex) { _, _ in refreshShelf() }
        .onChange(of: session.phase) { _, _ in refreshShelf() }
    }

    // MARK: - Trang

    private var pages: some View {
        TabView(selection: $page) {
            AudioPlaylistPage(
                isVisible: page == .playlist,
                drag: drag,
                onMinimize: { minimize(bySwipe: true) }
            )
            .tag(AudioPlayerPage.playlist)

            AudioDiscPage(
                referer: referer,
                isOnScreen: isAppActive && page == .disc && !isLeaving,
                drag: drag,
                onMinimize: { minimize(bySwipe: true) },
                isOnShelf: isOnShelf,
                canToggleShelf: hasBook,
                onToggleShelf: toggleShelf,
                onShowPage: { target in
                    withAnimation(.easeInOut(duration: 0.25)) { page = target }
                },
                openingErrorLink: $openingErrorLink
            )
            .tag(AudioPlayerPage.disc)

            AudioLyricsPage(
                referer: referer,
                isVisible: isAppActive && page == .lyrics && !isLeaving,
                drag: drag,
                onMinimize: { minimize(bySwipe: true) }
            )
            .tag(AudioPlayerPage.lyrics)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    // MARK: - Ngăn kéo

    private var sourcePageLink: SourceErrorLink? {
        guard let request = session.request else { return nil }
        return SourceErrorLink.resolve(from: nil, fallbacks: [request.detailUrl], host: referer)
    }

    private var drawerMenu: some View {
        AudioPlayerDrawerMenu(
            albumTitle: session.albumTitle,
            albumAuthor: session.albumAuthor,
            sourceName: session.request?.sourceName ?? "",
            trackCount: session.tracks.count,
            hasSourcePage: sourcePageLink != nil,
            hasCurrentTrack: session.currentTrackIndex != nil,
            lyricSources: session.lyricSources,
            selectedLyricSourceId: session.selectedLyricSourceId,
            playbackRate: session.playbackRate,
            sleepTimerSummary: session.sleepTimer.modeSummary,
            onOpenSourcePage: { openingSourcePage = sourcePageLink },
            onAddToPlaylist: { playlistRequest = PlaylistItemMapper.addRequestForCurrentTrack(of: AudioPlaybackSession.shared) },
            onSelectLyricSource: { AudioPlaybackSession.shared.selectLyricSource($0) },
            onSelectRate: { AudioPlaybackSession.shared.setPlaybackRate($0) },
            onOpenSleepTimer: { showingSleepTimer = true },
            onStop: { stopAndClose() }
        )
    }

    // MARK: - Vòng đời

    private func handleAppear() {
        if isCoveredByBrowser {
            isCoveredByBrowser = false
            return
        }
        AudioPlayerPresenter.install()
        guard session.isActive else {
            AppLogger.shared.log("❌ [AudioPlayerUI] Màn nghe hiện khi trình nghe không có album ⇒ đóng màn")
            closeAfterStop()
            return
        }
        session.attachScreen(token)
        refreshShelf()
        AppLogger.shared.log("🎵 [AudioPlayerUI] Màn nghe hiện (bookId=\(session.bookId))")
    }

    private func handleDisappear() {
        // Trình duyệt che màn (không phải rời màn): gỡ lúc này thì đĩa góc dưới hiện dưới trình duyệt và tiến độ bị lưu thừa.
        if openingErrorLink != nil || openingSourcePage != nil {
            isCoveredByBrowser = true
            return
        }
        session.detachScreen(token)
        AppLogger.shared.log("🎵 [AudioPlayerUI] Màn nghe đóng (nhạc \(session.isPlaying ? "vẫn phát" : "đang dừng"))")
    }

    // MARK: - Kệ

    private func refreshShelf() {
        let state = AudioShelfToggle.shelfState(session: session)
        if hasBook != (state != nil) { hasBook = state != nil }
        if isOnShelf != (state ?? false) { isOnShelf = state ?? false }
    }

    private func toggleShelf() {
        switch AudioShelfToggle.toggle(session: session) {
        case .added:
            ToastManager.shared.show(message: "Đã thêm album vào kệ", type: .success)
        case .removed:
            ToastManager.shared.show(message: "Đã bỏ album khỏi kệ", type: .info)
        case .notReady:
            ToastManager.shared.show(message: "Album chưa tải xong, thử lại sau giây lát.", type: .info)
        case .failed(let message):
            ToastManager.shared.show(message: "Không đổi được kệ: \(message)", type: .error)
        }
        refreshShelf()
    }

    // MARK: - Đóng màn

    /// Thu nhỏ: đóng màn, nhạc vẫn phát. Vuốt xuống ⇒ màn trượt nốt theo đà rồi đóng không animation.
    private func minimize(bySwipe: Bool) {
        guard !isLeaving else { return }
        isLeaving = true
        AppLogger.shared.log("🎵 [AudioPlayerUI] Thu nhỏ màn nghe (\(bySwipe ? "vuốt xuống" : "nút ⌄"))")
        guard bySwipe else {
            performDismiss(animated: true)
            return
        }
        drag.slideOut(duration: Self.slideOutDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.slideOutDuration) {
            MainActor.assumeIsolated {
                performDismiss(animated: false)
            }
        }
    }

    /// "Dừng hẳn" của ngăn kéo: dừng phiên (đĩa góc dưới tắt theo) rồi đóng màn.
    private func stopAndClose() {
        AppLogger.shared.log("🎵 [AudioPlayerUI] Dừng hẳn từ màn nghe")
        let shouldClose = !isLeaving
        isLeaving = true
        AudioPlaybackSession.shared.stop()
        if shouldClose {
            performDismiss(animated: true)
        }
    }

    /// Phiên đã dừng ở nơi khác ⇒ màn không còn gì để hiện.
    private func closeAfterStop() {
        guard !isLeaving else { return }
        isLeaving = true
        AppLogger.shared.log("🎵 [AudioPlayerUI] Trình nghe đã dừng ⇒ đóng màn nghe")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                performDismiss(animated: true)
            }
        }
    }

    private func performDismiss(animated: Bool) {
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
