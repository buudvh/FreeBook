import Foundation
import AVFoundation
import Observation
import SwiftData
import UIKit

/// Chủ **duy nhất** giữ `AVPlayer` của trình nghe âm thanh (tiện ích loại `audio`, hợp đồng tiện ích: `format` `audio` =
/// một bài, `album` = mỗi mục `toc` là một bài). `AVPlayer` **riêng**, không dùng chung với phim; sống lâu hơn màn nghe —
/// đóng màn thì nhạc vẫn phát (thanh mini đọc `AudioMiniPlayerState`), chỉ `stop()` mới dừng hẳn.
///
/// Pipeline (`+Loading` → `+TrackLoading` → `+Player`): `Book` + mục lục trên máy (phát được ngay) hoặc chi tiết + mục lục
/// từ nguồn (tạo `Book` để vào Lịch sử) → mỗi bài: `chap` (chỉ nguồn đầu tiên có `data`, không có ⇒ URL bài) → `track`
/// (đọc `data`, `headers`, `audios[0]`, lời) → `VideoSourceResolver` (`native` phát thẳng, `auto`/`webview` dò link; chỉ
/// nhúng được trang ⇒ lỗi) → `AVPlayerItem`. Media không đi qua pipeline text.
///
/// Phân xử với TTS và phim (`+AudioSession`): tại một thời điểm một bên giữ màn khoá — `AudioNowPlayingCoordinator`,
/// `VideoNowPlayingCoordinator`, `MediaNowPlayingOwnership`. Nhạc và TTS **không bao giờ cùng phát**: bên nào bắt đầu thì
/// bên kia dừng hẳn.
///
/// Stored property không `private` vì các file `+` nằm ở file khác. View chỉ đọc; mọi thay đổi đi qua hàm của session.
@MainActor
@Observable
final class AudioPlaybackSession {
    static let shared = AudioPlaybackSession()

    /// Một bài trong mục lục album (dòng `section` đã bị bỏ).
    struct Track: Identifiable, Equatable {
        /// Chỉ số trong mục lục đủ (`StoredChapterSnapshot.index`) — **thưa** (dòng section chiếm số), không phải offset
        /// của mảng `tracks`. Tiến độ (`Book.currentChapterIndex`) lưu đúng số này.
        let index: Int
        let title: String
        let url: String
        let host: String
        /// Nghệ sĩ = `description` của mục `toc` (chỉ có khi mục lục vừa tải từ nguồn); rỗng ⇒ hiện `albumAuthor`.
        var artist: String
        var id: Int { index }

        var displayTitle: String { title.isEmpty ? "Bài \(index + 1)" : title }
    }

    enum Phase: Equatable {
        /// Chưa mở album nào / đã `stop()`.
        case idle
        /// Đang đọc mục lục / chi tiết, hoặc đang lấy link bài (`chap` + `track` + dò link).
        case loading
        /// Đã có item, đang chờ đệm.
        case buffering
        case playing
        case paused
        /// Chữ lỗi + link "Mở link lỗi" (trang bài / `fetch` lỗi của script) — có thể `nil`.
        case failed(String, link: SourceErrorLink? = nil)
    }

    enum LyricsStatus: Equatable {
        /// Bài không có nguồn lời nào.
        case unavailable
        /// Có nguồn lời, chưa nạp (nạp sau khi bài bắt đầu phát / sẵn sàng).
        case pending
        case loading
        case loaded
        case failed(String)
    }

    /// Lỗi riêng của trình nghe.
    enum PlaybackError: LocalizedError {
        case embedOnly
        case trackNotFound

        var errorDescription: String? {
            switch self {
            case .embedOnly: return "Nguồn này chỉ phát được trong trang web."
            case .trackNotFound: return "Không tìm thấy bài cần phát."
            }
        }
    }

    static let minimumRate: Float = 0.5
    static let maximumRate: Float = 2
    static let playbackRates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
    /// Bấm "bài trước" khi bài đang phát quá mốc này (giây) ⇒ về đầu bài thay vì sang bài trước.
    static let restartThresholdSeconds: Double = 3
    /// Còn chừng này giây là hết bài ⇒ nạp sẵn link bài kế.
    static let prefetchLeadSeconds: Double = 15

    // MARK: - Trạng thái View đọc

    /// Lượt mở hiện tại; `nil` = trình nghe rảnh.
    var request: AudioListenRequest?
    /// Id album (`Book.bookId`) của lượt mở; rỗng khi rảnh.
    var bookId = ""
    var packageId = ""
    /// Tên album (chi tiết / `Book.title` / tên ở item danh sách).
    var albumTitle = ""
    /// Tác giả / nghệ sĩ của album (`detail.author`).
    var albumAuthor = ""
    var coverUrl = ""
    /// Album 18+ (`RepositoryFilterPolicy.isNsfwBook`) — xét lại mỗi lần đồng bộ thanh mini / màn khoá.
    var isNsfw = false
    /// Các bài phát được, theo thứ tự mục lục (không có dòng section).
    var tracks: [Track] = []
    /// Chỉ số mục lục (`Track.index`) của bài đang phát / đang nạp; `nil` khi chưa chọn được bài.
    var currentTrackIndex: Int?
    var phase: Phase = .idle
    /// `timeControlStatus != .paused` (gồm cả lúc chờ đệm giữa chừng).
    var isPlaying = false
    /// Cập nhật theo tick 0,5 s.
    var currentSeconds: Double = 0
    /// `0` = chưa biết độ dài (luồng trực tiếp / đang nạp).
    var durationSeconds: Double = 0
    /// Tốc độ người dùng chọn (`player.defaultRate`), `0.5…2`. Giữ qua các bài và các album trong lượt chạy app.
    var playbackRate: Float = 1
    /// Nhớ toàn app (`AudioPlaybackPreferences`).
    var repeatMode: AudioRepeatMode = AudioPlaybackPreferences.repeatMode
    /// Nhớ toàn app (`AudioPlaybackPreferences`).
    var isShuffled: Bool = AudioPlaybackPreferences.isShuffled
    /// Nguồn lời của bài đang phát (rỗng ⇒ `lyricsStatus == .unavailable`).
    var lyricSources: [AudioLyricSource] = []
    /// `AudioLyricSource.id` của nguồn đang hiện; `nil` khi chưa nạp được nguồn nào.
    var selectedLyricSourceId: Int?
    /// Lời đã đọc của nguồn đang chọn.
    var lyrics: AudioLyrics?
    var lyricsStatus: LyricsStatus = .unavailable
    /// Offset trong `lyrics.lines` của dòng đang hát (lời có mốc giờ); `nil` khi chưa tới dòng đầu / lời không mốc giờ.
    var currentLyricLineIndex: Int?

    // MARK: - Engine

    let player: AVPlayer
    /// Hẹn giờ tắt của lượt đang nghe (`+SleepTimer`); `stopSession` huỷ.
    let sleepTimer: MediaSleepTimer
    /// Container của lượt mở — presenter dùng để bơm `.modelContainer` khi mở lại màn từ thanh mini.
    @ObservationIgnored var modelContainer: ModelContainer?
    /// Presenter UI gắn vào: trình bày lại màn nghe gắn với phiên đang chạy (thanh mini, màn khoá).
    @ObservationIgnored var presentScreenHandler: ((_ animated: Bool, _ completion: @escaping () -> Void) -> Void)?
    /// Các màn nghe đang hiện (`attachScreen` / `detachScreen`, `+MiniPlayer`).
    @ObservationIgnored var attachedScreens = Set<ObjectIdentifier>()

    @ObservationIgnored var bookHost = ""
    /// Mô tả album (ghi vào `Book.desc` khi tạo).
    @ObservationIgnored var albumDesc = ""
    /// URL của **mọi** dòng mục lục theo chỉ số (kể cả section) — so khi làm mới mục lục (chỉ nhận thêm bài ở cuối).
    @ObservationIgnored var tocURLs: [String] = []
    /// `Book` + mục lục đã có trên máy (sẵn hoặc vừa ghi) ⇒ tiến độ lưu được.
    @ObservationIgnored var isBookReady = false
    /// `Book` do chính trình nghe tạo (chi tiết về muộn thì điền nốt metadata).
    @ObservationIgnored var createdBookId: String?
    /// `Book` có từ trước lượt mở ⇒ tên / tác giả / bìa của nó thắng chi tiết (giữ chỗ người dùng tự sửa).
    @ObservationIgnored var keepsStoredMetadata = false
    @ObservationIgnored var hasFreshDetail = false
    @ObservationIgnored var openGeneration = 0
    @ObservationIgnored var loadGeneration = 0
    @ObservationIgnored var lyricsGeneration = 0
    @ObservationIgnored var startTask: Task<Void, Never>?
    @ObservationIgnored var detailTask: Task<Void, Never>?
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var loadTask: Task<Void, Never>?
    @ObservationIgnored var prefetchTask: Task<Void, Never>?
    @ObservationIgnored var lyricsTask: Task<Void, Never>?
    @ObservationIgnored var coverTask: Task<Void, Never>?
    @ObservationIgnored var resolver: VideoSourceResolver?
    /// Resolver riêng của lượt nạp sẵn — `resolveSource` của một resolver huỷ lượt trước của chính nó.
    @ObservationIgnored var prefetchResolver: VideoSourceResolver?
    @ObservationIgnored var prefetchingIndex: Int?
    /// Bài kế đã thử nạp sẵn trong lượt phát bài hiện tại — lỗi thì không thử lại mỗi tick (sang bài sẽ nạp lại).
    @ObservationIgnored var prefetchAttemptedIndex: Int?
    /// Bản nạp sẵn theo chỉ số bài (`AudioPreparedTrack.isUsable`).
    @ObservationIgnored var preparedTracks: [Int: AudioPreparedTrack] = [:]
    /// Phải giữ strong ref: `AVURLAsset` chỉ giữ weak delegate của resource loader.
    @ObservationIgnored var hlsLoader: HLSPlaylistResourceLoader?
    @ObservationIgnored var timeObserverToken: Any?
    @ObservationIgnored var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored var itemNotificationTokens: [NSObjectProtocol] = []
    /// Item đã xử lý `readyToPlay` (tua giây đã lưu, nạp lời, quyết định tự phát) — KVO `status` và `timeControlStatus`
    /// về main không chắc theo thứ tự nên không dựa vào `phase`.
    @ObservationIgnored var handledReadyItem: ObjectIdentifier?
    @ObservationIgnored var lifecycleTokens: [NSObjectProtocol] = []
    /// Thứ tự phát của vòng hiện tại (chỉ số mục lục) — thường = thứ tự mục lục, xáo trộn = hoán vị bắt đầu bằng bài đang
    /// phát (`+Queue`).
    @ObservationIgnored var playOrder: [Int] = []
    /// Thứ tự của vòng kế (lặp album + xáo trộn), dựng sẵn để lượt nạp sẵn và lúc hết vòng chọn **cùng** một bài.
    @ObservationIgnored var upcomingCycleOrder: [Int]?
    /// Lượt nạp hiện tại tự phát khi item sẵn sàng (`false`: mở lại lúc khởi động / người dùng bấm dừng lúc đang nạp).
    @ObservationIgnored var shouldAutoplay = true
    /// Phim vừa giành âm thanh (`pauseForOtherMedia`; TTS thì dừng hẳn trình nghe — `stopForTTS`): item nạp xong không tự
    /// phát. Người dùng bấm phát / chọn bài, hoặc player thật sự chuyển sang phát (màn khoá) thì xoá.
    @ObservationIgnored var autoplayBlockedByOtherMedia = false
    /// Giây cần tua tới khi item sẵn sàng (chỉ khi > 2 giây); dùng xong thì về `nil`.
    @ObservationIgnored var pendingResumeSeconds: Int?
    @ObservationIgnored var wasPlaying = false
    /// Item hiện tại đã phát hết — lượt lưu sau đó không ghi giây ≈ độ dài bài.
    @ObservationIgnored var reachedEndOfItem = false
    @ObservationIgnored var lastProgressSaveUptime: TimeInterval = 0
    @ObservationIgnored var lastSavedProgress: (track: Int, seconds: Int)?
    /// Lúc (uptime) player chuyển từ phát sang dừng gần nhất — đoán "đang phát" khi thông báo ngắt (cuộc gọi) tới sau KVO.
    @ObservationIgnored var lastPauseUptime: TimeInterval = 0
    @ObservationIgnored var wasPlayingBeforeInterruption = false
    @ObservationIgnored var didActivateAudioSession = false
    /// Header của track đang phát — tải lời bài hát dạng URL.
    @ObservationIgnored var lyricHeaders: [String: String] = [:]
    /// Màn khoá: bìa (đã cắt vuông) của album đang mở.
    @ObservationIgnored var nowPlayingCover: (bookId: String, image: UIImage)?
    /// Thanh mini: tiến độ lần ghi trước (chỉ ghi khi lệch ≥ 0,5%).
    @ObservationIgnored var lastMiniProgress: Double = -1

    private init() {
        self.sleepTimer = MediaSleepTimer(medium: .audio)
        self.player = AVPlayer()
        installPlayerObservers()
        installLifecycleObservers()
        installRemoteActions()
        installSleepTimer()
    }

    // MARK: - Trạng thái suy ra

    /// Có album đang mở (kể cả đang nạp / dừng / lỗi).
    var isActive: Bool { request != nil }

    var currentTrack: Track? {
        guard let currentTrackIndex else { return nil }
        return track(at: currentTrackIndex)
    }

    /// Tên nghệ sĩ hiện cho bài đang phát: nghệ sĩ của bài → tác giả album.
    var currentArtist: String {
        let artist = currentTrack?.artist ?? ""
        return artist.isEmpty ? albumAuthor : artist
    }

    var currentPlaybackTime: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    func track(at index: Int) -> Track? {
        tracks.first { $0.index == index }
    }

    // MARK: - Mở / dừng

    /// Mở album. Cùng album đang mở ⇒ giữ nguyên phiên, không nạp lại (request chỉ bài khác thì chuyển bài, đang lỗi thì
    /// thử lại); album khác ⇒ dừng hẳn album cũ (lưu tiến độ) rồi nạp album mới.
    /// `autoplay == false` (app mở lại mục nghe gần nhất lúc khởi động): nạp tới bài + giây đã lưu rồi **dừng sẵn**, không
    /// dừng TTS / phim đang phát. `fromPlaylist` chỉ `PlaylistPlaybackCoordinator` truyền; lượt mở thường thoát chế độ playlist.
    func open(_ newRequest: AudioListenRequest, modelContainer: ModelContainer, autoplay: Bool = true, fromPlaylist: Bool = false) {
        if !fromPlaylist { PlaylistPlaybackCoordinator.shared.endAudio(reason: "mở album thường") }
        self.modelContainer = modelContainer
        let resolvedId = Self.resolvedBookId(for: newRequest, in: modelContainer)
        if isActive, bookId == resolvedId {
            reuseRunningSession(for: newRequest, autoplay: autoplay)
            return
        }
        if isActive { stop() }
        request = newRequest
        bookId = resolvedId
        packageId = newRequest.packageId
        albumTitle = newRequest.title ?? ""
        coverUrl = newRequest.coverUrl ?? ""
        bookHost = newRequest.host ?? ""
        isNsfw = RepositoryFilterPolicy.isNsfwBook(bookId: resolvedId, packageId: newRequest.packageId)
        phase = .loading
        shouldAutoplay = autoplay
        AppLogger.shared.log("🎵 [AudioPlayer] Mở album (bookId=\(resolvedId), tiện ích=\(newRequest.packageId), tự phát: \(autoplay ? "có" : "không"))")
        if autoplay {
            beginUserRequestedPlayback()
        }
        syncMiniPlayerState()
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

    private func reuseRunningSession(for newRequest: AudioListenRequest, autoplay: Bool) {
        if case .failed = phase {
            if autoplay { retry() }
            return
        }
        guard let target = newRequest.trackIndex, target != currentTrackIndex, track(at: target) != nil else { return }
        AppLogger.shared.log("🎵 [AudioPlayer] Mở lại album đang mở, chuyển sang bài \(target)")
        playTrack(at: target)
    }

    /// Dừng hẳn: lưu tiến độ, gỡ item, trả màn khoá + phiên âm thanh, xoá trạng thái mini. Idempotent.
    func stop() {
        stopSession(handingOverToTTS: false)
    }

    /// Thân chung của `stop()` và `stopForTTS()` (`+AudioSession`). `handingOverToTTS`: TTS đang giành phiên — không dựng
    /// lại lệnh / Now Playing của TTS và không tắt `AVAudioSession` (TTS vừa cấu hình nó).
    /// `keepsPlaybackSession` (`AudioAutoNextCoordinator` / `PlaylistPlaybackCoordinator`, ngay trước `open`): giữ màn khoá + phiên âm
    /// thanh + cầu nối mini — ở nền, tắt `AVAudioSession` rồi bật lại có thể không phát được nữa.
    func stopSession(handingOverToTTS: Bool, keepsPlaybackSession: Bool = false) {
        guard isActive else {
            AudioMiniPlayerState.shared.reset()
            return
        }
        saveProgress(reason: "đóng trình nghe")
        // Đóng hẳn / TTS giành ⇒ thôi chế độ playlist; lượt chuyển mục của playlist / tự sang thì giữ phiên (`keeps…`).
        if !keepsPlaybackSession { PlaylistPlaybackCoordinator.shared.endAudio(reason: handingOverToTTS ? "TTS giành phiên" : "đóng trình nghe") }
        let stoppedId = bookId
        openGeneration += 1
        loadGeneration += 1
        lyricsGeneration += 1
        for task in [startTask, detailTask, refreshTask, loadTask, prefetchTask, lyricsTask, coverTask] {
            task?.cancel()
        }
        startTask = nil
        detailTask = nil
        refreshTask = nil
        loadTask = nil
        prefetchTask = nil
        lyricsTask = nil
        coverTask = nil
        resolver?.cancel()
        resolver = nil
        prefetchResolver?.cancel()
        prefetchResolver = nil

        player.pause()
        detachCurrentItem()
        resetState()
        sleepTimer.reset()
        AudioPlaybackFlag.set(false)
        if !keepsPlaybackSession { AudioNowPlayingCoordinator.shared.release(handBackToTTS: !handingOverToTTS) }
        if handingOverToTTS {
            // Phiên âm thanh dùng chung giờ là của TTS: chỉ bỏ cờ, tắt lúc này là TTS câm.
            didActivateAudioSession = false
        } else if !keepsPlaybackSession {
            deactivateAudioSessionIfIdle()
        }
        // Giữ cầu nối mini: `open` ngay sau ghi đè hết — reset ở giữa làm thanh mini nhận một nhịp `isActive == false`.
        if !keepsPlaybackSession { AudioMiniPlayerState.shared.reset() }
        AppLogger.shared.log("🎵 [AudioPlayer] Đóng trình nghe (bookId=\(stoppedId)\(handingOverToTTS ? ", nhường TTS" : ""))")
    }

    private func resetState() {
        request = nil
        bookId = ""
        packageId = ""
        albumTitle = ""
        albumAuthor = ""
        coverUrl = ""
        isNsfw = false
        tracks = []
        currentTrackIndex = nil
        phase = .idle
        isPlaying = false
        currentSeconds = 0
        durationSeconds = 0
        resetLyrics(sources: [], headers: [:])
        bookHost = ""
        albumDesc = ""
        tocURLs = []
        isBookReady = false
        createdBookId = nil
        keepsStoredMetadata = false
        hasFreshDetail = false
        prefetchingIndex = nil
        prefetchAttemptedIndex = nil
        preparedTracks = [:]
        playOrder = []
        upcomingCycleOrder = nil
        shouldAutoplay = true
        autoplayBlockedByOtherMedia = false
        pendingResumeSeconds = nil
        wasPlaying = false
        reachedEndOfItem = false
        lastSavedProgress = nil
        wasPlayingBeforeInterruption = false
        nowPlayingCover = nil
        lastMiniProgress = -1
    }

    private static func resolvedBookId(for request: AudioListenRequest, in container: ModelContainer) -> String {
        let resolved = request.resolveBookId(in: container.mainContext)
        guard resolved.isEmpty else { return resolved }
        // Không tiện ích, không link (không thể xảy ra với item danh sách) ⇒ id riêng của lượt mở.
        AppLogger.shared.log("❌ [AudioPlayer] Album thiếu cả tiện ích lẫn link chi tiết ⇒ dùng id tạm")
        return UUID().uuidString
    }
}
