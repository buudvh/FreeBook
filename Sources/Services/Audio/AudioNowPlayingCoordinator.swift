import Foundation
import MediaPlayer
import UIKit

/// Màn khoá / Trung tâm điều khiển cho trình nghe âm thanh: `MPNowPlayingInfoCenter` + remote command khi nhạc **giữ
/// phiên** — bản sao cách làm của `VideoNowPlayingCoordinator`.
///
/// `MPRemoteCommandCenter` dùng chung với TTS (target gắn một lần, không gỡ) và phim ⇒ phân xử bằng cờ
/// `isHoldingSession` (`MediaNowPlayingOwnership` gộp cờ của phim + nhạc cho TTS hỏi):
/// - Nhạc giữ phiên từ lúc bắt đầu phát (`claim()`, sau khi TTS đã tắt hẳn + phim đã nhường —
///   `AudioPlaybackSession.prepareAudioForPlayback`) tới khi đóng hẳn / bài lỗi (`release(handBackToTTS: true)`), hoặc khi
///   TTS bắt đầu/tiếp tục đọc (`yieldToTTS()` — trả phiên rồi **dừng hẳn** trình nghe: nhạc và TTS không bao giờ cùng
///   phát), hoặc khi phim giành âm thanh (`yieldToOtherMedia()` — nhạc chỉ tạm dừng rồi trả phiên). Cả hai lối đều không
///   dựng lại TTS.
/// - Chỉ gỡ đúng token target của nhạc (`removeTarget(token)`), không bao giờ `removeTarget(nil)`.
/// - Now Playing của nhạc đánh dấu bằng `MPNowPlayingInfoPropertyExternalContentIdentifier` (tiền tố `contentIdPrefix`):
///   TTS cũng ghi loại media `.audio` nên không phân biệt được theo loại như phim. Trả phiên thì xoá Now Playing nếu đang
///   là của nhạc — TTS ghi Now Playing bằng cách **trộn** vào bản đang có, để sót là TTS mang tên bài hát.
@MainActor
final class AudioNowPlayingCoordinator {
    /// Hành động của session, gắn một lần lúc `AudioPlaybackSession` khởi tạo. Chưa từng mở trình nghe ⇒ `nil`.
    struct Actions {
        let play: () -> Void
        let pause: () -> Void
        let togglePlayPause: () -> Void
        /// Tua tương đối (giây, âm = lùi).
        let skip: (Double) -> Void
        let nextTrack: () -> Void
        let previousTrack: () -> Void
        /// Tua tới giây tuyệt đối (kéo thanh tiến độ trên màn khoá).
        let seek: (Double) -> Void
        /// Phim chiếm âm thanh: tạm dừng + bài đang nạp không tự phát, không lưu gì thêm.
        let pauseForOtherMedia: () -> Void
        /// TTS bắt đầu / tiếp tục đọc: dừng hẳn trình nghe (`AudioPlaybackSession.stopForTTS`) — không dựng lại TTS, không
        /// tắt `AVAudioSession`. Không có album ⇒ không làm gì.
        let stopForTTS: () -> Void
    }

    static let shared = AudioNowPlayingCoordinator()
    static let contentIdPrefix = "audioPlayer:"

    /// Nhạc đang giữ màn khoá / Trung tâm điều khiển.
    private(set) var isHoldingSession = false
    var actions: Actions?

    private var registrations: [(command: MPRemoteCommand, token: Any)] = []
    /// Ảnh màn khoá lần ghi trước — cùng ảnh thì dùng lại `MPMediaItemArtwork`.
    private var cachedArtwork: (image: UIImage, artwork: MPMediaItemArtwork)?

    private init() {}

    // MARK: - Giữ / trả phiên

    /// Gọi mỗi lần nhạc bắt đầu phát; lặp lại an toàn. Caller phải cho phim nhường **trước** (`release` của phim tắt lệnh
    /// tua — chạy sau `claim` này là mất nút của nhạc).
    func claim() {
        guard !isHoldingSession else { return }
        isHoldingSession = true
        registerTargets()
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        // Không bật tua ±15 s: có lệnh tua thì iOS hiện nút ±15 trên màn khoá **thay** cho nút bài trước/sau. Album nhạc cần
        // nút chuyển bài (plan đã duyệt); tua chỉ có trong màn nghe. Tắt tường minh vì TTS có thể đã bật trước đó.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = true
        UIApplication.shared.beginReceivingRemoteControlEvents()
        AppLogger.shared.log("🎛️ [AudioNowPlaying] Trình nghe âm thanh giữ phiên điều khiển màn khoá")
    }

    /// Trả phiên: gỡ target của nhạc, tắt các lệnh chỉ nhạc/phim dùng, xoá Now Playing nếu đang là của nhạc.
    /// `handBackToTTS`: dựng lại lệnh / Now Playing của TTS (đóng trình nghe, bài lỗi). TTS / phim tự giành phiên thì không cần.
    func release(handBackToTTS: Bool) {
        guard isHoldingSession else { return }
        isHoldingSession = false
        for registration in registrations {
            registration.command.removeTarget(registration.token)
        }
        registrations = []
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
        let infoCenter = MPNowPlayingInfoCenter.default()
        if Self.isAudioPlayerInfo(infoCenter.nowPlayingInfo) {
            infoCenter.nowPlayingInfo = nil
            infoCenter.playbackState = .stopped
        }
        AppLogger.shared.log("🎛️ [AudioNowPlaying] Trình nghe âm thanh trả phiên điều khiển màn khoá (trả cho TTS: \(handBackToTTS ? "có" : "không"))")
        if handBackToTTS {
            TTSManager.shared.reclaimRemoteControlsAfterVideo()
        }
    }

    /// TTS bắt đầu/tiếp tục đọc (hook ở `TTSManager+NowPlaying`: `setRemoteCommandsEnabled(true)` khi nhạc đang giữ phiên,
    /// và mọi lần `setSystemNowPlayingPlaybackState(.playing)`) ⇒ trình nghe **dừng hẳn** — nhạc và TTS không bao giờ cùng
    /// phát, không bao giờ cùng lúc có thanh nhạc mini lẫn widget TTS. Nhạc luôn được báo, kể cả khi chưa giữ phiên (album
    /// đang dừng / bài đang nạp).
    ///
    /// Thứ tự cố ý: trả phiên **trước** (`release(handBackToTTS: false)`) rồi mới dừng session — `release` bên trong
    /// `stopForTTS` gặp `guard isHoldingSession` và thôi, không bao giờ gọi `reclaimRemoteControlsAfterVideo` (đệ quy vào
    /// `setRemoteCommandsEnabled` lúc TTS đang tự cấu hình). Chưa từng mở trình nghe ⇒ `actions == nil`, chỉ trả phiên (nếu có).
    func yieldToTTS() {
        if isHoldingSession {
            AppLogger.shared.log("⏹️ [AudioNowPlaying] TTS bắt đầu đọc ⇒ nhường điều khiển màn khoá, dừng hẳn nhạc")
            release(handBackToTTS: false)
        }
        actions?.stopForTTS()
    }

    /// Phim giành âm thanh (`VideoPlaybackSession.prepareAudioForPlayback` / người dùng chọn phát phim có tiếng): nhạc chỉ
    /// tạm dừng (album vẫn mở), luôn được báo kể cả khi chưa giữ phiên (bài đang nạp không tự phát chồng).
    func yieldToOtherMedia() {
        actions?.pauseForOtherMedia()
        guard isHoldingSession else { return }
        AppLogger.shared.log("⏸️ [AudioNowPlaying] Phim bắt đầu phát ⇒ tạm dừng nhạc, nhường điều khiển màn khoá")
        release(handBackToTTS: false)
    }

    // MARK: - Now Playing

    /// Không giữ phiên thì bỏ qua. `contentId` = `bookId` của album (đánh dấu Now Playing là của nhạc).
    func publish(
        metadata: AudioNowPlayingMetadata,
        contentId: String,
        elapsed: Double,
        duration: Double,
        rate: Double,
        defaultRate: Double,
        isPlaying: Bool,
        hasNextTrack: Bool
    ) {
        guard isHoldingSession else { return }
        var info: [String: Any] = [:]
        apply(metadata, contentId: contentId, to: &info)
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        } else {
            info[MPNowPlayingInfoPropertyIsLiveStream] = true
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed.isFinite ? max(0, elapsed) : 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = defaultRate

        let infoCenter = MPNowPlayingInfoCenter.default()
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = isPlaying ? .playing : .paused
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = hasNextTrack
    }

    /// Đang nạp bài mới mà nhạc vẫn giữ phiên: báo dừng (`rate 0`) với tên bài mới — màn khoá không chạy tiếp đồng hồ cũ.
    func publishLoading(metadata: AudioNowPlayingMetadata, contentId: String, hasNextTrack: Bool) {
        guard isHoldingSession else { return }
        var info: [String: Any] = [:]
        apply(metadata, contentId: contentId, to: &info)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
        let infoCenter = MPNowPlayingInfoCenter.default()
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = .paused
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = hasNextTrack
    }

    /// `TTSManager.stopPlayback` xoá thẳng `nowPlayingInfo` không qua guard ⇒ tick của nhạc hỏi hàm này rồi tự dựng lại.
    func needsRepublish() -> Bool {
        guard isHoldingSession else { return false }
        return !Self.isAudioPlayerInfo(MPNowPlayingInfoCenter.default().nowPlayingInfo)
    }

    private func apply(_ metadata: AudioNowPlayingMetadata, contentId: String, to info: inout [String: Any]) {
        info[MPMediaItemPropertyTitle] = metadata.title
        if let artist = metadata.artist {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let albumTitle = metadata.albumTitle {
            info[MPMediaItemPropertyAlbumTitle] = albumTitle
        }
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyExternalContentIdentifier] = Self.contentIdPrefix + contentId
        guard let image = metadata.artwork else { return }
        if let cachedArtwork, cachedArtwork.image === image {
            info[MPMediaItemPropertyArtwork] = cachedArtwork.artwork
            return
        }
        let artwork = Self.makeArtwork(image)
        cachedArtwork = (image: image, artwork: artwork)
        info[MPMediaItemPropertyArtwork] = artwork
    }

    /// `nonisolated`: closure trả ảnh được hệ thống gọi ở luồng bất kỳ — dựng ngoài main actor.
    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private static func isAudioPlayerInfo(_ info: [String: Any]?) -> Bool {
        guard let identifier = info?[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String else { return false }
        return identifier.hasPrefix(contentIdPrefix)
    }

    // MARK: - Target

    private func registerTargets() {
        guard registrations.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()

        add(center.playCommand) { actions, _ in actions.play() }
        add(center.pauseCommand) { actions, _ in actions.pause() }
        add(center.togglePlayPauseCommand) { actions, _ in actions.togglePlayPause() }
        add(center.nextTrackCommand) { actions, _ in actions.nextTrack() }
        add(center.previousTrackCommand) { actions, _ in actions.previousTrack() }
        add(center.changePlaybackPositionCommand, payload: Self.positionTime) { actions, position in
            guard position >= 0 else { return }
            actions.seek(position)
        }
    }

    private nonisolated static func positionTime(_ event: MPRemoteCommandEvent) -> Double {
        (event as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? -1
    }

    private nonisolated static func noPayload(_ event: MPRemoteCommandEvent) -> Double {
        0
    }

    /// `payload` đọc dữ liệu của event ngay trong handler (event không được mang sang Task).
    private func add(
        _ command: MPRemoteCommand,
        payload: @escaping (MPRemoteCommandEvent) -> Double = AudioNowPlayingCoordinator.noPayload,
        perform: @escaping @MainActor (Actions, Double) -> Void
    ) {
        let token = command.addTarget { [weak self] event in
            let owner = self
            let value = payload(event)
            Task { @MainActor in
                guard let owner, owner.isHoldingSession, let actions = owner.actions else { return }
                perform(actions, value)
            }
            return .success
        }
        registrations.append((command: command, token: token))
    }
}
