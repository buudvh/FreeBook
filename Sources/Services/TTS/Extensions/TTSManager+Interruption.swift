import Foundation
import AVFoundation

extension TTSManager {
    internal func handleInterruption(notification: Notification) {
        #if DEBUG
        logRemoteTrace("handleInterruption", details: "userInfo:\(notification.userInfo ?? [:])")
        #endif
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            AppLogger.shared.log("🔊 [TTSManager] Audio session interruption began. isPlaying = \(self.isPlaying)")
            if isPlaying {
                self.wasPlayingBeforeInterruption = true
                self.pause()
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                self.isAudioSessionConfigured = false
            }
        case .ended:
            AppLogger.shared.log("🔊 [TTSManager] Audio session interruption ended. wasPlayingBeforeInterruption = \(self.wasPlayingBeforeInterruption)")
            if self.wasPlayingBeforeInterruption {
                self.wasPlayingBeforeInterruption = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    if !self.isPlaying {
                        AppLogger.shared.log("🔊 [TTSManager] Resuming TTS playback after interruption.")
                        self.configureAudioSession()
                        self.resume()
                    }
                }
            }
        @unknown default:
            break
        }
    }

    internal func handleRouteChange(notification: Notification) {
        #if DEBUG
        logRemoteTrace("handleRouteChange", details: "userInfo:\(notification.userInfo ?? [:])")
        #endif
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        AppLogger.shared.log("🔊 [TTSManager] Route change: reason=\(reason.rawValue)")

        switch reason {
        case .oldDeviceUnavailable:
            if isPlaying {
                AppLogger.shared.log("🔊 [TTSManager] Old device unavailable. Reconfiguring and restarting current paragraph.")
                let currentIdx = currentParagraphIndex
                stopCurrentPlayback()
                configureAudioSession()
                currentParagraphIndex = currentIdx
                speakCurrent()
            }
        case .newDeviceAvailable:
            if isPlaying {
                configureAudioSession()
            }
        default:
            break
        }
    }

    internal func handleMediaServicesReset() {
        #if DEBUG
        logRemoteTrace("handleMediaServicesReset")
        #endif
        AppLogger.shared.log("🔊 [TTSManager] Media services were reset. Rebuilding audio engine.")
        let wasPlaying = isPlaying
        let currentIdx = currentParagraphIndex
        isAudioSessionConfigured = false

        setupAudioEngine()

        if let engine = audioEngine {
            NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange, object: engine)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    self.handleEngineConfigChange()
                }
                .store(in: &cancellables)
        }

        if wasPlaying && currentIdx >= 0 && currentIdx < paragraphs.count {
            configureAudioSession()
            self.isPlaying = true
            speakCurrent()
        }
    }

    internal func handleEngineConfigChange() {
        #if DEBUG
        logRemoteTrace("handleEngineConfigChange")
        #endif
        AppLogger.shared.log("🔊 [TTSManager] Engine configuration changed.")

        guard isPlaying else { return }
        let currentIdx = currentParagraphIndex

        stopCurrentPlayback()
        configureAudioSession()

        currentParagraphIndex = currentIdx
        speakCurrent()
    }
}
