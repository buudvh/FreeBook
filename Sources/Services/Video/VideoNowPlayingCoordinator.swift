import Foundation
import MediaPlayer
import UIKit

/// Màn khoá / Trung tâm điều khiển cho video: `MPNowPlayingInfoCenter` + remote command khi video **giữ phiên**.
///
/// `MPRemoteCommandCenter` là một instance dùng chung với TTS (`TTSNowPlayingController` gắn target một lần lúc khởi
/// động, không gỡ) ⇒ phân xử bằng cờ `isHoldingSession`:
/// - Video giữ phiên từ lúc bắt đầu phát (`claim()`) tới khi không còn item phát native — đóng hẳn, item lỗi,
///   chuyển sang trang nhúng (`release(handBackToTTS: true)`) — hoặc khi TTS bắt đầu/tiếp tục phát (`yieldToTTS()` —
///   video tạm dừng rồi trả phiên). Đổi tập/server: vẫn giữ phiên nhưng báo trạng thái dừng (`publishLoading`).
/// - Trong lúc giữ: mọi hàm ghi Now Playing / bật-tắt lệnh của TTS (`TTSManager+NowPlaying`) và handler của
///   `TTSNowPlayingController` đều bỏ qua; target của video chỉ tồn tại trong lúc giữ phiên.
/// - Chỉ gỡ đúng token target của video (`removeTarget(token)`), không bao giờ `removeTarget(nil)` (sẽ gỡ cả của TTS).
@MainActor
final class VideoNowPlayingCoordinator {
    /// Hành động của session, gắn một lần lúc session khởi tạo.
    struct Actions {
        let play: () -> Void
        let pause: () -> Void
        let togglePlayPause: () -> Void
        /// Tua tương đối (giây, âm = lùi).
        let skip: (Double) -> Void
        let nextEpisode: () -> Void
        /// Tua tới giây tuyệt đối (kéo thanh tiến độ trên màn khoá).
        let seek: (Double) -> Void
        /// TTS chiếm phiên: chỉ tạm dừng, không lưu thêm gì khác.
        let pauseForTTS: () -> Void
    }

    static let shared = VideoNowPlayingCoordinator()

    /// Video đang giữ màn khoá / Trung tâm điều khiển. TTS đọc cờ này để bỏ qua lệnh và không ghi đè Now Playing.
    private(set) var isHoldingSession = false
    var actions: Actions?

    private var registrations: [(command: MPRemoteCommand, token: Any)] = []

    private init() {}

    // MARK: - Giữ / trả phiên

    /// Gọi mỗi lần video bắt đầu phát; lặp lại an toàn.
    func claim() {
        guard !isHoldingSession else { return }
        isHoldingSession = true
        registerTargets()
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = false
        UIApplication.shared.beginReceivingRemoteControlEvents()
        AppLogger.shared.log("🎛️ [VideoNowPlaying] Video giữ phiên điều khiển màn khoá")
    }

    /// Trả phiên: gỡ target của video, tắt các lệnh chỉ video dùng, xoá Now Playing nếu đang là của video.
    /// `handBackToTTS`: dựng lại trạng thái lệnh/Now Playing của TTS (đóng trình phát). TTS tự giành phiên
    /// (`yieldToTTS`) thì không cần — TTS đang tự cấu hình ngay sau đó.
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
        if Self.isVideoInfo(infoCenter.nowPlayingInfo) {
            infoCenter.nowPlayingInfo = nil
            infoCenter.playbackState = .stopped
        }
        AppLogger.shared.log("🎛️ [VideoNowPlaying] Video trả phiên điều khiển màn khoá")
        if handBackToTTS {
            TTSManager.shared.reclaimRemoteControlsAfterVideo()
        }
    }

    /// TTS bắt đầu/tiếp tục phát (hook ở `TTSManager+NowPlaying`). Video luôn được báo (`pauseForTTS`) — kể cả khi
    /// chưa giữ phiên: item đang nạp thì không tự phát khi sẵn sàng, trang nhúng thì dừng media. Đang giữ phiên thì
    /// trả phiên luôn.
    func yieldToTTS() {
        actions?.pauseForTTS()
        guard isHoldingSession else { return }
        AppLogger.shared.log("⏸️ [VideoNowPlaying] TTS bắt đầu phát ⇒ tạm dừng video, nhường điều khiển màn khoá")
        release(handBackToTTS: false)
    }

    // MARK: - Now Playing

    /// Không giữ phiên thì bỏ qua (video đang nhường TTS).
    func publish(
        title: String,
        album: String,
        elapsed: Double,
        duration: Double,
        rate: Double,
        defaultRate: Double,
        isPlaying: Bool,
        hasNextEpisode: Bool
    ) {
        guard isHoldingSession else { return }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyAlbumTitle] = album
        info[MPMediaItemPropertyArtist] = album
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
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
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = hasNextEpisode
    }

    /// Đang nạp item mới (đổi tập / đổi server / thử lại) mà video vẫn giữ phiên: báo dừng (`rate 0`, `.paused`) với tên
    /// tập mới — màn khoá không chạy tiếp đồng hồ của item cũ. Không đặt độ dài (thiếu độ dài ≠ phát trực tiếp).
    func publishLoading(title: String, album: String) {
        guard isHoldingSession else { return }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyAlbumTitle] = album
        info[MPMediaItemPropertyArtist] = album
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
        let infoCenter = MPNowPlayingInfoCenter.default()
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = .paused
    }

    /// `TTSManager.stopPlayback` (file gốc, không sửa được) xoá thẳng `nowPlayingInfo` mà không qua guard ⇒ tick của
    /// video hỏi hàm này rồi tự dựng lại.
    func needsRepublish() -> Bool {
        guard isHoldingSession else { return false }
        return !Self.isVideoInfo(MPNowPlayingInfoCenter.default().nowPlayingInfo)
    }

    private static func isVideoInfo(_ info: [String: Any]?) -> Bool {
        guard let raw = info?[MPNowPlayingInfoPropertyMediaType] as? NSNumber else { return false }
        return raw.uintValue == MPNowPlayingInfoMediaType.video.rawValue
    }

    // MARK: - Target

    private func registerTargets() {
        guard registrations.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]

        add(center.playCommand) { actions, _ in actions.play() }
        add(center.pauseCommand) { actions, _ in actions.pause() }
        add(center.togglePlayPauseCommand) { actions, _ in actions.togglePlayPause() }
        add(center.nextTrackCommand) { actions, _ in actions.nextEpisode() }
        add(center.skipForwardCommand, payload: Self.skipInterval) { actions, interval in
            actions.skip(interval)
        }
        add(center.skipBackwardCommand, payload: Self.skipInterval) { actions, interval in
            actions.skip(-interval)
        }
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

    /// `nonisolated`: được truyền làm `payload` (kiểu hàm không gắn actor).
    private nonisolated static func skipInterval(_ event: MPRemoteCommandEvent) -> Double {
        let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
        return interval > 0 ? interval : 10
    }

    /// `payload` đọc dữ liệu của event ngay trong handler (event không được mang sang Task).
    private func add(
        _ command: MPRemoteCommand,
        payload: @escaping (MPRemoteCommandEvent) -> Double = VideoNowPlayingCoordinator.noPayload,
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
