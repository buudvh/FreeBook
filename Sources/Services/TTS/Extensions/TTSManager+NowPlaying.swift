import Foundation
import MediaPlayer
import UIKit

extension TTSManager {
    internal func setRemoteCommandsEnabled(_ enabled: Bool) {
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

        AppLogger.shared.log("🔍 [NP] publishNowPlayingInfo title=\(metadata.displayBookTitle) artist=\(metadata.displayChapterTitle) rate=\(currentRate) para=\(paragraphIndex)/\(paragraphCount) hasArtwork=\(metadata.artwork != nil)") // REMOVE_AFTER_NOWPLAYING_DIAGNOSIS
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
