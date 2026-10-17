import Foundation
import AVFoundation
import Observation
import SwiftData
import UIKit

/// Chủ **duy nhất** giữ `AVPlayer` của trình phát video (bất biến 4 plan đợt 2), sống lâu hơn màn hình:
/// - Màn hình (`VideoPlayerScreen`) chỉ `attachScreen()` / `detachScreen()`. Thu nhỏ màn thì phim vẫn phát; hub đọc
///   trạng thái qua cầu nối `VideoMiniPlayerState` (không observe session này).
/// - Chỉ `stop()` (nút Đóng X, đóng từ hub, hoặc mở phim khác) mới dừng hẳn.
/// - Giữ luôn `layerView` (`AVPlayerLayer`) và PiP: thu nhỏ màn không làm chết PiP, khôi phục từ PiP gắn lại đúng layer.
///
/// Pipeline nạp: mục lục tập → `chap` (server) → `track` → `VideoSourceResolver` → `AVPlayerItem` hoặc trang nhúng.
/// Media không đi qua pipeline text (`ChapterContentRepository.load`, `ChapterTextNormalizer`…); `data` của server
/// được truyền nguyên văn vào `track`.
///
/// Stored property không `private` vì các file `+` nằm ở file khác (`private` của Swift là phạm vi file).
/// View chỉ đọc; mọi thay đổi đi qua hàm của session.
@MainActor
@Observable
final class VideoPlaybackSession {
    static let shared = VideoPlaybackSession()

    struct Episode: Identifiable, Equatable {
        /// Chỉ số chương trong mục lục (`StoredChapterSnapshot.index`) — không phải offset mảng.
        let index: Int
        let title: String
        let url: String
        let host: String
        /// Dòng tiêu đề nhóm tập (`type: "section"`) — không phát được.
        var isSection: Bool = false
        var id: Int { index }

        var displayTitle: String { title.isEmpty ? "Tập \(index + 1)" : title }
    }

    enum Phase: Equatable {
        case idle
        case loadingEpisodes
        case loadingServers
        case resolving
        case buffering
        case playing
        case embed
        case failed(String)
    }

    /// Trang nhúng kèm hai header duy nhất được đưa tới trang (hợp đồng extension: chỉ `User-Agent` và `Referer`).
    enum EmbedContent: Equatable {
        /// `referer` đặt lên `URLRequest` của trang; `nil` = không gửi.
        case page(URL, referer: String?, userAgent: String)
        /// `loadHTMLString` không gắn được header ⇒ Referer của request con do `baseURL` quyết định.
        case html(String, baseURL: URL?, userAgent: String)
    }

    // MARK: - Trạng thái View đọc

    /// Lượt mở hiện tại; `nil` = session rảnh (chưa mở phim nào hoặc đã `stop()`).
    var launch: BookContentLaunch?
    var bookTitle = ""
    var episodes: [Episode] = []
    var currentEpisodeIndex = 0
    var servers: [VideoServer] = []
    var selectedServerIndex: Int?
    var phase: Phase = .idle
    var embedContent: EmbedContent?
    /// Giây cần tua tới khi bấm "Bỏ qua"; `nil` = không nằm trong khoảng `timeSkip` nào.
    var skipTargetSeconds: Double?
    var currentCueText = ""
    var hasSubtitles = false
    var subtitlesEnabled = true
    /// `timeControlStatus != .paused` (gồm cả lúc chờ đệm).
    var isPlaying = false
    var isBuffering = false
    /// Cập nhật theo tick 0,5 giây — chỉ các subview nhỏ (thời gian, thanh tua) được đọc.
    var currentSeconds: Double = 0
    var durationSeconds: Double = 0
    var bufferedSeconds: Double = 0
    /// Tốc độ người dùng chọn (`player.defaultRate`); nhấn giữ 2× không đổi giá trị này.
    var playbackRate: Float = 1
    var isBoosting = false
    var isPictureInPicturePossible = false
    var isPictureInPictureActive = false

    // MARK: - Engine

    let player: AVPlayer
    let layerView: VideoPlayerLayerView
    @ObservationIgnored var pictureInPicture: VideoPictureInPictureCoordinator?
    /// Container của lượt mở đầu tiên — presenter dùng để bơm `.modelContainer` khi mở lại màn từ hub/PiP.
    @ObservationIgnored var modelContainer: ModelContainer?
    /// Presenter toàn cục gắn vào (`VideoPlayerPresenter.install`): trình bày lại màn hình gắn với session đang chạy.
    @ObservationIgnored var presentScreenHandler: ((@escaping () -> Void) -> Void)?
    @ObservationIgnored var isScreenAttached = false
    @ObservationIgnored var isInBackground = false

    @ObservationIgnored var bookHost = ""
    @ObservationIgnored var openGeneration = 0
    @ObservationIgnored var loadGeneration = 0
    @ObservationIgnored var startTask: Task<Void, Never>?
    @ObservationIgnored var loadTask: Task<Void, Never>?
    @ObservationIgnored var subtitleTask: Task<Void, Never>?
    @ObservationIgnored var resolver: VideoSourceResolver?
    /// Phải giữ strong ref: `AVURLAsset` chỉ giữ weak delegate của resource loader.
    @ObservationIgnored var hlsLoader: HLSPlaylistResourceLoader?
    @ObservationIgnored var timeObserverToken: Any?
    @ObservationIgnored var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored var itemNotificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored var lifecycleTokens: [NSObjectProtocol] = []
    @ObservationIgnored var cues: [VideoSubtitleCue] = []
    @ObservationIgnored var timeSkips: [VideoTimeSkip] = []
    /// Giây cần tua tới khi item sẵn sàng (chỉ khi > 5 giây); dùng xong thì về `nil`.
    @ObservationIgnored var pendingResumeSeconds: Int?
    @ObservationIgnored var wasPlaying = false
    /// Item hiện tại đã phát hết: KVO `.paused` (và các lượt lưu sau đó) không được ghi giây ≈ độ dài phim.
    @ObservationIgnored var reachedEndOfItem = false
    @ObservationIgnored var lastProgressSaveUptime: TimeInterval = 0
    @ObservationIgnored var lastSavedProgress: (episode: Int, seconds: Int)?
    @ObservationIgnored var didActivateAudioSession = false
    @ObservationIgnored var idleTimerBaseline: Bool?

    private init() {
        let player = AVPlayer()
        self.player = player
        let layerView = VideoPlayerLayerView()
        layerView.playerLayer.player = player
        self.layerView = layerView
        installPlayerObservers()
        installLifecycleObservers()
        installPictureInPicture()
        installRemoteActions()
    }

    // MARK: - Trạng thái suy ra

    var isActive: Bool { launch != nil }

    var currentEpisode: Episode? {
        episodes.first { $0.index == currentEpisodeIndex }
    }

    /// Tập phát được kế tiếp — bỏ qua dòng section.
    var nextEpisode: Episode? {
        guard let position = episodes.firstIndex(where: { $0.index == currentEpisodeIndex }) else { return nil }
        return episodes[(position + 1)...].first { !$0.isSection }
    }

    var currentEpisodeLabel: String { currentEpisode?.displayTitle ?? "" }

    var canTryAnotherServer: Bool { servers.count > 1 }

    var serverDefaultsKey: String { "videoServer.\(launch?.bookId ?? "")" }

    var selectedServerTitle: String {
        guard let index = selectedServerIndex, servers.indices.contains(index) else { return "?" }
        return servers[index].title
    }

    /// Đang có item phát native (không phải nhúng, không đang nạp/lỗi) — điều khiển phát/tua dùng được.
    var hasPlayableItem: Bool {
        embedContent == nil && (phase == .playing || phase == .buffering)
    }

    var currentPlaybackTime: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    // MARK: - Mở / dừng

    /// Mở phim từ router. Cùng phim đang chạy ⇒ giữ nguyên phiên (router chỉ tập khác thì chuyển tập);
    /// phim khác ⇒ dừng hẳn phim cũ (lưu tiến độ) rồi nạp phim mới.
    func open(_ newLaunch: BookContentLaunch, modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        if let current = launch, current.bookId == newLaunch.bookId {
            reuseRunningSession(for: newLaunch)
            return
        }
        if launch != nil { stop() }
        launch = newLaunch
        bookTitle = newLaunch.bookTitle ?? ""
        currentEpisodeIndex = max(0, newLaunch.chapterIndex)
        beginStart()
    }

    func beginStart() {
        openGeneration += 1
        let generation = openGeneration
        startTask?.cancel()
        startTask = Task { [weak self] in
            await self?.start(openGeneration: generation)
        }
    }

    private func reuseRunningSession(for newLaunch: BookContentLaunch) {
        if case .failed = phase {
            retry()
            return
        }
        guard newLaunch.chapterIndex != currentEpisodeIndex,
              let target = episodes.first(where: { $0.index == newLaunch.chapterIndex }),
              !target.isSection else { return }
        AppLogger.shared.log("🎬 [VideoPlayer] Mở lại phim đang phát, chuyển sang tập \(target.index)")
        selectEpisode(target)
    }

    /// Dừng hẳn: lưu tiến độ, gỡ item, trả phiên Now Playing + audio, xoá trạng thái mini. Idempotent.
    func stop() {
        guard let stopped = launch else {
            VideoMiniPlayerState.shared.reset()
            return
        }
        saveProgress(reason: "đóng trình phát")
        openGeneration += 1
        loadGeneration += 1
        startTask?.cancel()
        startTask = nil
        loadTask?.cancel()
        loadTask = nil
        subtitleTask?.cancel()
        subtitleTask = nil
        resolver?.cancel()
        resolver = nil

        player.pause()
        detachCurrentItem()
        pictureInPicture?.stop()
        launch = nil
        resetPlaybackState()
        restoreIdleTimer()
        VideoNowPlayingCoordinator.shared.release(handBackToTTS: true)
        deactivateAudioSessionIfIdle()
        VideoMiniPlayerState.shared.reset()
        AppLogger.shared.log("🎬 [VideoPlayer] Đóng trình phát (bookId=\(stopped.bookId))")
    }

    private func resetPlaybackState() {
        bookTitle = ""
        bookHost = ""
        episodes = []
        currentEpisodeIndex = 0
        servers = []
        selectedServerIndex = nil
        phase = .idle
        embedContent = nil
        skipTargetSeconds = nil
        currentCueText = ""
        hasSubtitles = false
        cues = []
        timeSkips = []
        isPlaying = false
        isBuffering = false
        currentSeconds = 0
        durationSeconds = 0
        bufferedSeconds = 0
        isBoosting = false
        playbackRate = 1
        player.defaultRate = 1
        pendingResumeSeconds = nil
        wasPlaying = false
        reachedEndOfItem = false
        lastSavedProgress = nil
    }

    // MARK: - Màn hình gắn / gỡ

    func attachScreen() {
        isScreenAttached = true
        refreshLayerAttachment()
        VideoMiniPlayerState.shared.isActive = false
    }

    /// Màn hình biến mất mà session chưa `stop()` ⇒ thu nhỏ: phim chạy nền, hub hiện mục Video.
    func detachScreen() {
        isScreenAttached = false
        refreshLayerAttachment()
        guard launch != nil else {
            VideoMiniPlayerState.shared.reset()
            return
        }
        saveProgress(reason: "thu nhỏ")
        syncMiniPlayerState()
        AppLogger.shared.log("🎬 [VideoPlayer] Thu nhỏ trình phát, phim vẫn chạy nền")
    }

    /// Ghi cầu nối cho hub. Chỉ bật `isActive` khi màn hình không hiện; closure gán lại mỗi lần vì `reset()` xoá chúng.
    func syncMiniPlayerState() {
        guard launch != nil, !isScreenAttached else { return }
        let mini = VideoMiniPlayerState.shared
        let subtitle = currentEpisodeLabel
        if mini.title != bookTitle { mini.title = bookTitle }
        if mini.subtitle != subtitle { mini.subtitle = subtitle }
        if mini.isPlaying != isPlaying { mini.isPlaying = isPlaying }
        mini.onTogglePlay = { [weak self] in self?.togglePlayPause() }
        mini.onReopen = { [weak self] in self?.requestScreen() }
        mini.onStop = { [weak self] in self?.stop() }
        if !mini.isActive { mini.isActive = true }
    }

    /// Trình bày lại màn hình gắn với phiên đang chạy (hub, PiP, nút phát của mục Video khi đang nhúng).
    func requestScreen(completion: (() -> Void)? = nil) {
        guard launch != nil, !isScreenAttached, let handler = presentScreenHandler else {
            completion?()
            return
        }
        handler {
            completion?()
        }
    }
}
