import Foundation
import AVFoundation

@MainActor
public final class TTSAudioEngineController {
    public private(set) var audioEngine: AVAudioEngine?
    public private(set) var playerNode: AVAudioPlayerNode?
    public private(set) var pitchNode: AVAudioUnitTimePitch?
    public private(set) var eqNode: AVAudioUnitEQ?

    public var onInterruptionBegan: (() -> Void)?
    public var onInterruptionEnded: (() -> Void)?

    public init() {}

    public func configureEngine(speed: Double, pitch: Double) {
        if audioEngine == nil {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let pitchUnit = AVAudioUnitTimePitch()

            let eq = AVAudioUnitEQ(numberOfBands: 2)
            let band0 = eq.bands[0]
            band0.filterType = .lowPass
            band0.frequency = 6500.0
            band0.bandwidth = 1.0
            band0.bypass = false

            let band1 = eq.bands[1]
            band1.filterType = .highShelf
            band1.frequency = 7500.0
            band1.bandwidth = 1.0
            band1.gain = -12.0
            band1.bypass = false
            eq.bypass = false

            engine.attach(player)
            engine.attach(eq)
            engine.attach(pitchUnit)

            engine.connect(player, to: eq, format: nil)
            engine.connect(eq, to: pitchUnit, format: nil)
            engine.connect(pitchUnit, to: engine.mainMixerNode, format: nil)

            self.audioEngine = engine
            self.playerNode = player
            self.pitchNode = pitchUnit
            self.eqNode = eq
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


}
