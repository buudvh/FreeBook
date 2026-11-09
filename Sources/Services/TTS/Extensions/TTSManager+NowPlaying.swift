import Foundation
import MediaPlayer
import UIKit

/// Phân xử với phim (`VideoNowPlayingCoordinator`) và trình nghe âm thanh (`AudioNowPlayingCoordinator`): khi một trong
/// hai giữ phiên điều khiển màn khoá (`MediaNowPlayingOwnership.isHeldByMedia`), mọi hàm ghi Now Playing / bật-tắt lệnh ở
/// file này bỏ qua để không ghi đè trạng thái của bên đó. TTS bắt đầu/tiếp tục phát (bật lệnh, hoặc đặt trạng thái
/// `.playing`) thì bên đang giữ tạm dừng và trả phiên trước, rồi TTS cấu hình như thường. Riêng trạng thái `.playing` luôn
/// báo cả phim lẫn nhạc (kể cả khi không giữ phiên) để item đang nạp không tự phát chồng và trang nhúng dừng.
extension TTSManager {
    internal func setRemoteCommandsEnabled(_ enabled: Bool) {
        let video = VideoNowPlayingCoordinator.shared
        let audio = AudioNowPlayingCoordinator.shared
        if video.isHoldingSession || audio.isHoldingSession {
            // Chỉ TTS bắt đầu/tiếp tục phát mới bật lệnh ⇒ bên đang giữ nhường; lệnh tắt thì bỏ qua (giữ nút của bên đó).
            guard enabled else { return }
            if video.isHoldingSession { video.yieldToTTS() }
            if audio.isHoldingSession { audio.yieldToTTS() }
        }
        #if DEBUG
        logRemoteTrace("setRemoteCommandsEnabled(\(enabled))")
        #endif
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = enabled
        commandCenter.pauseCommand.isEnabled = enabled
        commandCenter.togglePlayPauseCommand.isEnabled = enabled
        commandCenter.nextTrackCommand.isEnabled = enabled
        commandCenter.previousTrackCommand.isEnabled = enabled

        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false

        if enabled {
            UIApplication.shared.beginReceivingRemoteControlEvents()
        } else {
            UIApplication.shared.endReceivingRemoteControlEvents()
        }
    }

    internal func syncRemoteCommandState() {
        guard !MediaNowPlayingOwnership.isHeldByMedia else { return }
        let commandCenter = MPRemoteCommandCenter.shared()
        let active = !playingBookId.isEmpty && showFloatingWidget
        let playing = active && isPlaying
        let paused = active && !isPlaying
        commandCenter.playCommand.isEnabled = paused
        commandCenter.pauseCommand.isEnabled = playing
        commandCenter.togglePlayPauseCommand.isEnabled = active
        commandCenter.nextTrackCommand.isEnabled = active
        commandCenter.previousTrackCommand.isEnabled = active
        #if DEBUG
        logRemoteTrace("syncRemoteCommandState", details: "active:\(active), playing:\(playing), paused:\(paused)")
        #endif
    }

    @MainActor
    internal func setSystemNowPlayingPlaybackState(_ state: MPNowPlayingPlaybackState) {
        if state == .playing {
            // TTS thật sự bắt đầu/tiếp tục đọc ⇒ báo phim + nhạc cả khi chưa giữ phiên (đang nạp item / bài, đang nhúng
            // trang). Không hook ở `setRemoteCommandsEnabled(true)`: `reclaimRemoteControlsAfterVideo` cũng gọi nó
            // khi TTS chỉ đang tạm dừng.
            VideoNowPlayingCoordinator.shared.yieldToTTS()
            AudioNowPlayingCoordinator.shared.yieldToTTS()
        } else if MediaNowPlayingOwnership.isHeldByMedia {
            return
        }
        let center = MPNowPlayingInfoCenter.default()
        var info = center.nowPlayingInfo ?? [:]
        let currentRate = (state == .playing) ? 1.0 : 0.0
        let pIndex = self.currentParagraphIndex
        let pCount = self.paragraphs.count
        let duration = Double(max(1, pCount))
        let elapsed = min(duration, Double(max(0, pIndex)))
        let progress = duration > 0 ? min(1.0, max(0.0, elapsed / duration)) : 0.0

        info[MPNowPlayingInfoPropertyPlaybackRate] = currentRate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = self.speed
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackProgress] = progress

        center.nowPlayingInfo = info
        center.playbackState = state
    }

    internal func publishNowPlayingInfo(using metadata: NowPlayingStaticMetadata) {
        // Metadata nạp bất đồng bộ có thể về sau khi phim / nhạc đã giữ phiên ⇒ không ghi đè.
        guard !MediaNowPlayingOwnership.isHeldByMedia else { return }
        let paragraphIndex = currentParagraphIndex
        let paragraphCount = paragraphs.count
        let liveIsPlaying = isPlaying
        let liveSpeed = speed

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = metadata.displayBookTitle

        let currentPart = paragraphCount == 0 ? "" : " (Đoạn \(paragraphIndex + 1)/\(paragraphCount))"
        info[MPMediaItemPropertyArtist] = metadata.displayChapterTitle + currentPart
        info.removeValue(forKey: MPNowPlayingInfoPropertyIsLiveStream)
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue

        let currentRate = liveIsPlaying ? 1.0 : 0.0
        let duration = Double(max(1, paragraphCount))
        let elapsed = min(duration, Double(max(0, paragraphIndex)))
        let progress = duration > 0 ? min(1.0, max(0.0, elapsed / duration)) : 0.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = currentRate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = liveSpeed
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackProgress] = progress

        if let artwork = metadata.artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        } else {
            info.removeValue(forKey: MPMediaItemPropertyArtwork)
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = liveIsPlaying ? .playing : .paused
    }

    /// Phim hoặc trình nghe âm thanh vừa trả phiên (đóng trình phát / trình nghe): dựng lại lệnh / Now Playing của TTS —
    /// lúc bên đó giữ phiên các hàm ghi ở file này đều bỏ qua nên trạng thái hệ thống đang là của bên đó.
    internal func reclaimRemoteControlsAfterVideo() {
        guard !playingBookId.isEmpty, showFloatingWidget else {
            setRemoteCommandsEnabled(false)
            return
        }
        setRemoteCommandsEnabled(true)
        syncRemoteCommandState()
        updateNowPlayingInfo()
    }

    internal func downloadNowPlayingCoverIfNeeded(for key: NowPlayingStaticMetadataKey) {
        guard !key.coverUrl.isEmpty, nowPlayingCoverDownloadKey != key else { return }
        nowPlayingCoverDownloadKey = key

        ImageCacheManager.shared.downloadAndSaveCover(urlStr: key.coverUrl, bookId: key.bookId) { [weak self] image in
            guard image != nil else { return }
            DispatchQueue.main.async {
                guard let self,
                      self.playingBookId == key.bookId,
                      self.showFloatingWidget else { return }
                self.nowPlayingCoverDownloadKey = nil
                if self.nowPlayingStaticMetadata?.key == key {
                    self.nowPlayingStaticMetadata = nil
                }
                self.updateNowPlayingInfo()
            }
        }
    }
}
