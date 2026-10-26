import Foundation
import AVFoundation
import Observation
import SwiftData
import UIKit

/// Chủ **duy nhất** giữ `AVPlayer` của trình phát video (bất biến 4 plan đợt 2), sống lâu hơn màn hình:
/// - Màn hình (`VideoPlayerScreen`) chỉ `attachScreen(_:)` / `detachScreen(_:)` (theo từng màn). Thu nhỏ màn thì phim
///   vẫn phát; hub đọc trạng thái qua cầu nối `VideoMiniPlayerState` (không observe session này).
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
    var isPictureInPicturePossible = false
    var isPictureInPictureActive = false
    /// Tăng mỗi lần PiP bật xong (`didStart`) — `VideoPlayerScreen` tự thu nhỏ khi người dùng bấm PiP lúc app đang mở.
    var pictureInPictureStartCount = 0
    /// Tăng mỗi lần cần dừng media của trang nhúng đang hiện (TTS bắt đầu đọc) — `VideoEmbedWebView` so giá trị này.
    var embedPauseRequest = 0
    /// Thông báo ngắn trên khung phim khi tự đổi link vì mất tiếng; `nil` = không hiện. Tự ẩn sau vài giây.
    var playbackNotice: String?
    /// Mức chất lượng của item đang phát (HLS ≥ 2 mức, cao → thấp); rỗng ⇒ menu không có mục Chất lượng (`+Quality`).
    var qualityOptions: [VideoQualityOption] = []
    /// Lựa chọn của người dùng, giữ qua các tập; `nil` = Tự động.
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
    @ObservationIgnored var pictureInPicture: VideoPictureInPictureCoordinator?
    /// Container của lượt mở đầu tiên — presenter dùng để bơm `.modelContainer` khi mở lại màn từ hub/PiP.
    @ObservationIgnored var modelContainer: ModelContainer?
    /// Presenter toàn cục gắn vào (`VideoPlayerPresenter.install`): trình bày lại màn hình gắn với session đang chạy.
    @ObservationIgnored var presentScreenHandler: ((@escaping () -> Void) -> Void)?
    /// Các màn đang gắn (khoá = controller của từng màn). Hai màn có thể cùng gắn trong chốc lát khi mở lại trình phát.
    @ObservationIgnored var attachedScreens = Set<ObjectIdentifier>()
    @ObservationIgnored var isInBackground = false
    /// Video đã nhường TTS (`pauseForTTS`): item nạp xong không tự phát. Người dùng bấm phát / chọn tập / chọn server /
    /// thử lại, hoặc player thật sự chuyển sang phát (PiP, màn khoá) thì xoá. Video đang tắt tiếng không bật cờ này.
    @ObservationIgnored var autoplayBlockedByTTS = false
    /// Background task giữ app sống trong nhịp chờ PiP lúc vào nền (`+Lifecycle`).
    @ObservationIgnored var audioFallbackBackgroundTask: UIBackgroundTaskIdentifier = .invalid
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
        // Chỉ phim mới mới áp tuỳ chọn tắt tiếng; đặt TRƯỚC `beginUserRequestedPlayback` (tắt tiếng ⇒ không dừng TTS).
        let startMuted = VideoMutePolicy.shouldStartMuted(packageId: newLaunch.extensionPackageId)
        AppLogger.shared.log("🎬 [VideoPlayer] Mở phim mới: \(startMuted ? "tắt tiếng" : "có tiếng") theo tuỳ chọn «\(VideoMutePolicy.current.title)»")
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
        // Gỡ `launch` TRƯỚC khi tắt PiP: AVKit có thể hỏi khôi phục giao diện ngay trong `stop()` — guard
        // `launch != nil` của `restoreFromPictureInPicture` chặn việc mở lại màn của phim vừa đóng.
        launch = nil
        pictureInPicture?.stop()
        resetPlaybackState()
        refreshIdleTimer()
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
        autoplayBlockedByTTS = false
        resetOfflineState()
        qualityTask?.cancel()
        qualityTask = nil
        qualityOptions = []
        selectedQuality = nil
        resetPlaybackSource()
    }

    // MARK: - Màn hình gắn / gỡ

    /// `owner` = controller riêng của từng màn (`VideoPlayerController`). Mở lại trình phát khi màn cũ chưa gỡ xong thì
    /// `onAppear` của màn mới có thể tới trước `onDisappear` của màn cũ ⇒ đếm theo từng màn, không dùng một cờ chung.
    func attachScreen(_ owner: AnyObject) {
        attachedScreens.insert(ObjectIdentifier(owner))
        refreshLayerAttachment()
        refreshIdleTimer()
        VideoMiniPlayerState.shared.isActive = false
    }

    /// Màn **cuối cùng** biến mất mà session chưa `stop()` ⇒ thu nhỏ: phim chạy nền, hub hiện mục Video.
    /// Gỡ màn không có trong danh sách (gọi lặp) thì bỏ qua.
    func detachScreen(_ owner: AnyObject) {
        guard attachedScreens.remove(ObjectIdentifier(owner)) != nil, attachedScreens.isEmpty else { return }
        refreshLayerAttachment()
        refreshIdleTimer()
        guard launch != nil else {
            VideoMiniPlayerState.shared.reset()
            return
        }
        saveProgress(reason: "thu nhỏ")
        syncMiniPlayerState()
        AppLogger.shared.log("🎬 [VideoPlayer] Thu nhỏ trình phát, phim vẫn chạy nền")
    }

    /// Ghi cầu nối cho hub. Chỉ bật `isActive` khi màn hình không hiện; closure gán lại mỗi lần vì `reset()` xoá chúng.
    /// Trang nhúng chết cùng màn (WKWebView bị huỷ khi thu nhỏ) ⇒ hub không báo "đang phát" mà mời chạm để mở lại.
    func syncMiniPlayerState() {
        guard launch != nil, !isScreenAttached else { return }
        let mini = VideoMiniPlayerState.shared
        let isEmbed = embedContent != nil
        let subtitle = isEmbed
            ? [currentEpisodeLabel, "Chạm để mở lại"].filter { !$0.isEmpty }.joined(separator: " · ")
            : currentEpisodeLabel
        let playing = isEmbed ? false : isPlaying
        mini.packageId = launch?.extensionPackageId ?? ""
        if mini.title != bookTitle { mini.title = bookTitle }
        if mini.subtitle != subtitle { mini.subtitle = subtitle }
        if mini.isPlaying != playing { mini.isPlaying = playing }
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
