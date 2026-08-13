import Foundation
import MediaPlayer

@MainActor
public final class TTSNowPlayingController {
    public var onPlayCommand: (() -> Void)?
    public var onPauseCommand: (() -> Void)?
    public var onNextCommand: (() -> Void)?
    public var onPreviousCommand: (() -> Void)?

    public init() {}

    public func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.onPlayCommand?()
            }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.onPauseCommand?()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if MPNowPlayingInfoCenter.default().playbackState == .playing {
                    self?.onPauseCommand?()
                } else {
                    self?.onPlayCommand?()
                }
            }
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.onNextCommand?()
            }
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.onPreviousCommand?()
            }
            return .success
        }
    }

    public func updateNowPlayingInfo(
        title: String,
        author: String,
        chapterTitle: String,
        playbackRate: Double,
        playbackState: MPNowPlayingPlaybackState
    ) {
        let center = MPNowPlayingInfoCenter.default()
        center.playbackState = playbackState

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = chapterTitle
        info[MPMediaItemPropertyArtist] = author
        info[MPMediaItemPropertyAlbumTitle] = title
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate

        center.nowPlayingInfo = info
    }

    public func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
