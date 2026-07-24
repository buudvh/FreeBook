import Foundation
import AVFoundation

@MainActor
public final class TTSAudioEngineController {
    public private(set) var audioEngine: AVAudioEngine?
    public private(set) var playerNode: AVAudioPlayerNode?
    public private(set) var pitchNode: AVAudioUnitTimePitch?

    public var onInterruptionBegan: (() -> Void)?
    public var onInterruptionEnded: (() -> Void)?

    public init() {
        setupAudioSessionNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func configureEngine(speed: Double, pitch: Double) {
        if audioEngine == nil {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let pitchUnit = AVAudioUnitTimePitch()

            engine.attach(player)
            engine.attach(pitchUnit)

            engine.connect(player, to: pitchUnit, format: nil)
            engine.connect(pitchUnit, to: engine.mainMixerNode, format: nil)

            self.audioEngine = engine
            self.playerNode = player
            self.pitchNode = pitchUnit
        }

        pitchNode?.rate = Float(speed)
        pitchNode?.pitch = Float(pitch)
    }

    public func play() {
        guard let engine = audioEngine, let player = playerNode else { return }
        do {
            if !engine.isRunning {
                try engine.start()
            }
            player.play()
        } catch {
            AppLogger.shared.log("❌ [TTSAudioEngineController] Không thể khởi chạy AVAudioEngine: \(error.localizedDescription)")
        }
    }

    public func pause() {
        playerNode?.pause()
    }

    public func stop() {
        playerNode?.stop()
        audioEngine?.stop()
    }

    private func setupAudioSessionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        if type == .began {
            onInterruptionBegan?()
        } else if type == .ended {
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    onInterruptionEnded?()
                }
            }
        }
    }
}
