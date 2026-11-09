import Foundation
import AVFoundation
import Observation
import SwiftData
import UIKit

/// Chủ **duy nhất** giữ `AVPlayer` của trình phát video (bất biến 4 plan đợt 2), sống lâu hơn màn hình:
/// - Màn hình (`VideoPlayerScreen`) và cửa sổ nhỏ (`VideoMiniPlayerWindowManager`) chỉ `attachScreen(_:isMiniPlayer:)` /
///   `detachScreen(_:)` (`+Screens`). Thu nhỏ vào hub thì phim vẫn phát; hub đọc trạng thái qua cầu nối
///   `VideoMiniPlayerState` (không observe session này).
/// - Chỉ `stop()` (nút Đóng X, ✕ của cửa sổ nhỏ, đóng từ hub, hoặc mở phim khác) mới dừng hẳn.
/// - Giữ luôn `layerView` (`AVPlayerLayer`): màn hình và cửa sổ nhỏ chỉ chuyển view này qua lại, phim không ngắt.
/// - Không có Hình trong hình của hệ thống (bỏ ở 1.3.751): rời app thì chỉ phát tiếng; công tắc `VideoLeaveAppPolicy` (mặc
///   định bật) còn thu màn xem / cửa sổ nhỏ vào hub (`VideoLeaveToHubCoordinator`), không dừng phim.
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
        /// Chữ lỗi + link "Mở link lỗi" của lớp phủ lỗi (`episodeErrorLink`) — link mất cùng lúc với trạng thái lỗi.
        case failed(String, link: SourceErrorLink? = nil)
    }

    /// Trang nhúng kèm hai header duy nhất được đưa tới trang (hợp đồng extension: chỉ `User-Agent` và `Referer`).
    /// `userAgent` = **chỉ** header `User-Agent` tiện ích tự khai; `nil` ⇒ `VideoEmbedWebView` dùng UA theo chế độ
    /// máy tính/điện thoại của tiện ích (`WebContentConfigurator`).
    enum EmbedContent: Equatable {
        /// `referer` đặt lên `URLRequest` của trang; `nil` = không gửi.
        case page(URL, referer: String?, userAgent: String?)
        /// `loadHTMLString` không gắn được header ⇒ Referer của request con do `baseURL` quyết định.
        case html(String, baseURL: URL?, userAgent: String?)
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
    /// Tăng mỗi lần cần dừng media của trang nhúng đang hiện (TTS bắt đầu đọc) — `VideoEmbedWebView` so giá trị này.
    var embedPauseRequest = 0
    /// Thông báo ngắn trên khung phim khi tự đổi link vì mất tiếng; `nil` = không hiện. Tự ẩn sau vài giây.
    var playbackNotice: String?
    /// Mức chất lượng của item đang phát (HLS ≥ 2 mức, cao → thấp); rỗng ⇒ menu không có mục Chất lượng (`+Quality`).
    var qualityOptions: [VideoQualityOption] = []
    /// Lựa chọn của người dùng, nhớ theo tiện ích (`VideoQualityPreferenceStore`); `nil` = Tự động.
    var selectedQuality: VideoQualityOption?
    /// Tập đang xem có bản tải trọn vẹn ⇒ hàng chip/menu server có "Bản tải" (`+Offline`).
    var hasOfflineCopy = false
    /// Item đang phát là bản tải trên máy.
    var isPlayingOffline = false
    /// `AVPlayer.isMuted` (đổi qua `setMuted`, `+Transport`); mở phim mới thì đặt theo `VideoMutePolicy`.
    var isMuted = false

    // MARK: - Engine

    let player: AVPlayer
    let layerView: VideoPlayerLayerView
    /// Hẹn giờ tắt của lượt đang xem (`+SleepTimer`); `stop()` huỷ, trừ lượt tự sang phim đề xuất (`open(keepsSleepTimer:)`).
    let sleepTimer: MediaSleepTimer
    /// Container của lượt mở đầu tiên — presenter dùng để bơm `.modelContainer` khi mở lại màn từ hub/PiP.
    @ObservationIgnored var modelContainer: ModelContainer?
    /// Presenter toàn cục gắn vào (`VideoPlayerPresenter.install`): trình bày lại màn hình gắn với session đang chạy
    /// (`animated == false` khi cửa sổ nhỏ đã tự nở lên chỗ khung phim).
    @ObservationIgnored var presentScreenHandler: ((_ animated: Bool, _ completion: @escaping () -> Void) -> Void)?
    /// Các màn đang gắn (khoá = controller của từng màn, hoặc cửa sổ nhỏ). Hai màn có thể cùng gắn trong chốc lát khi mở
    /// lại trình phát.
    @ObservationIgnored var attachedScreens = Set<ObjectIdentifier>()
    /// Phần của `attachedScreens` là cửa sổ nhỏ (`+Screens`).
    @ObservationIgnored var miniPlayerScreens = Set<ObjectIdentifier>()
    /// Cửa sổ nhỏ gắn vào: màn to vừa gắn (mở lại / mở phim) ⇒ cửa sổ nhỏ tự ẩn.
    @ObservationIgnored var onFullScreenAttached: (() -> Void)?
    /// Cửa sổ nhỏ gắn vào: phiên vừa `stop()` (có thể ngay sau đó mở phim mới — tự sang phim đề xuất).
    @ObservationIgnored var onDidStop: (() -> Void)?
    @ObservationIgnored var isInBackground = false
    /// Đang phát lúc app rời trạng thái active — vào nền thì phát tiếp chỉ tiếng (`+Lifecycle`).
    @ObservationIgnored var wasPlayingWhenResigned = false
    /// Video đã nhường TTS (`pauseForTTS`): item nạp xong không tự phát. Người dùng bấm phát / chọn tập / chọn server /
    /// thử lại, hoặc player thật sự chuyển sang phát (màn khoá, hub) thì xoá. Video đang tắt tiếng không bật cờ này.
    @ObservationIgnored var autoplayBlockedByTTS = false
    @ObservationIgnored var qualityTask: Task<Void, Never>?
    /// Tập người dùng chọn xem trực tuyến dù đã có bản tải (chip "Trực tuyến"); đổi tập thì bỏ (`+Offline`).
    @ObservationIgnored var onlineOverrideEpisodeIndex: Int?
    /// Lúc (uptime) gần nhất bật lại server + nạp lại bản tải sau lỗi phát — chặn vòng lặp lỗi liên tục.
    @ObservationIgnored var offlineLastRetryUptime: TimeInterval?

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
    /// Track + kết quả phân giải của lượt đang phát: log chẩn đoán và phương án dự phòng khi mất tiếng
    /// (`+AudioFallback`). Xoá ở mỗi lượt nạp mới và khi `stop()`.
    @ObservationIgnored var currentTrack: VideoTrack?
    @ObservationIgnored var sourceResolution: VideoSourceResolution?
    @ObservationIgnored var audioCheckTask: Task<Void, Never>?
    /// `loadGeneration` đã kiểm tiếng — mỗi lượt nạp (kể cả mỗi phương án dự phòng) chỉ kiểm một lần.
    @ObservationIgnored var audioCheckedGeneration: Int?
    @ObservationIgnored var noticeTask: Task<Void, Never>?
    /// Giây ghi vào Lịch sử khi đang nhúng trang: 0, trừ khi tự chuyển sang nhúng vì mất tiếng (giữ giây đang xem).
    @ObservationIgnored var embedProgressSeconds = 0
    /// Dòng báo hiện khi phim vừa mở **bắt đầu phát** (`open(startNotice:)` — tự sang phim đề xuất). Hiện ngay lúc mở thì
    /// lượt nạp tập (`prepareForNewLoad` → `resetPlaybackSource`) xoá mất.
    @ObservationIgnored var pendingStartNotice: String?
    /// `open(fromPlaylist: true)` đang dừng phim cũ để mở mục kế của playlist ⇒ `stop()` không thôi chế độ playlist.
    @ObservationIgnored var isSwitchingPlaylistItem = false
    /// Màn khoá (`+NowPlaying`): bìa của phim đang mở, tác giả, lượt nạp bìa.
    @ObservationIgnored var nowPlayingCover: (bookId: String, image: UIImage)?
    @ObservationIgnored var nowPlayingAuthor = ""
    @ObservationIgnored var nowPlayingCoverTask: Task<Void, Never>?
    /// Thu nhỏ lúc đang phát (`noteMinimizing`, `+Screens`): tới mốc uptime này, màn cuối rời phiên mà player bị dừng thì
    /// phát tiếp. `0` = không giữ (người dùng bấm dừng xoá ngay).
    @ObservationIgnored var keepPlayingDeadline: TimeInterval = 0
    /// Tắt NSFW ⇒ thu phim 18+ vào hub + tắt tiếng theo cài đặt (`+NsfwGuard`): observer + giá trị công tắc lần trước (chỉ
    /// xử lý lúc chuyển bật → tắt).
    @ObservationIgnored var nsfwDefaultsObserver: NSObjectProtocol?
    @ObservationIgnored var lastIncludesNsfw = false

    private init() {
        self.sleepTimer = MediaSleepTimer(medium: .video)
        let player = AVPlayer()
        self.player = player
        let layerView = VideoPlayerLayerView()
        layerView.playerLayer.player = player
        self.layerView = layerView
        installPlayerObservers()
        installLifecycleObservers()
        installRemoteActions()
        installNsfwGuard()
        installSleepTimer()
    }

    // MARK: - Trạng thái suy ra

    var isActive: Bool { launch != nil }

    var isScreenAttached: Bool { !attachedScreens.isEmpty }

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
    /// `muteOverride` (tự sang phim đề xuất) thay `VideoMutePolicy` cho phim mới; `startNotice` hiện khi phim bắt đầu phát.
    /// `keepsSleepTimer` (tự sang phim đề xuất): giữ hẹn giờ tắt của phim vừa hết — ngủ quên thì chuỗi phim đề xuất vẫn dừng
    /// đúng giờ. Người dùng tự mở phim khác ⇒ hẹn giờ huỷ cùng `stop()`. `fromPlaylist` chỉ lượt mở mục playlist
    /// (`VideoWatchModel.PlaylistStart`) truyền; lượt mở thường thoát chế độ playlist.
    func open(
        _ newLaunch: BookContentLaunch,
        modelContainer: ModelContainer,
        muteOverride: Bool? = nil,
        startNotice: String? = nil,
        keepsSleepTimer: Bool = false,
        fromPlaylist: Bool = false
    ) {
        if !fromPlaylist { PlaylistPlaybackCoordinator.shared.endVideo(reason: "mở phim thường") }
        self.modelContainer = modelContainer
        if let current = launch, current.bookId == newLaunch.bookId {
            reuseRunningSession(for: newLaunch)
            return
        }
        if launch != nil {
            let carriedTimer = keepsSleepTimer ? sleepTimer.schedule : nil
            isSwitchingPlaylistItem = fromPlaylist
            stop()
            isSwitchingPlaylistItem = false
            if let carriedTimer { sleepTimer.restore(carriedTimer) }
        }
        launch = newLaunch
        bookTitle = newLaunch.bookTitle ?? ""
        currentEpisodeIndex = max(0, newLaunch.chapterIndex)
        pendingStartNotice = startNotice
        loadNowPlayingCover(for: newLaunch)
        // Chỉ phim mới mới áp tuỳ chọn tắt tiếng; đặt TRƯỚC `beginUserRequestedPlayback` (tắt tiếng ⇒ không dừng TTS).
        let startMuted = muteOverride
            ?? VideoMutePolicy.shouldStartMuted(bookId: newLaunch.bookId, packageId: newLaunch.extensionPackageId)
        let reason = muteOverride == nil ? "theo tuỳ chọn «\(VideoMutePolicy.current.title)»" : "giữ như phim vừa xem (tự sang)"
        AppLogger.shared.log("🎬 [VideoPlayer] Mở phim mới: \(startMuted ? "tắt tiếng" : "có tiếng") \(reason)")
        setMuted(startMuted)
        beginUserRequestedPlayback()
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
        if !isSwitchingPlaylistItem { PlaylistPlaybackCoordinator.shared.endVideo(reason: "đóng trình phát") }
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
        launch = nil
        resetPlaybackState()
        refreshIdleTimer()
        sleepTimer.reset()
        VideoNowPlayingCoordinator.shared.release(handBackToTTS: true)
        deactivateAudioSessionIfIdle()
        VideoMiniPlayerState.shared.reset()
        AppLogger.shared.log("🎬 [VideoPlayer] Đóng trình phát (bookId=\(stopped.bookId))")
        onDidStop?()
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
        VideoNativePlaybackFlag.set(false)
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
        autoplayBlockedByTTS = false
        pendingStartNotice = nil
        resetNowPlayingCover()
        resetOfflineState()
        qualityTask?.cancel()
        qualityTask = nil
        qualityOptions = []
        selectedQuality = nil
        resetPlaybackSource()
    }
}
