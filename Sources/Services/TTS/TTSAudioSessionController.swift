import Foundation
import AVFoundation

public final class TTSAudioSessionController: @unchecked Sendable {
    public init() {}

    public func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)
    }

    public func configureAudioSession() -> Bool {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [
                    .duckOthers,
                    .allowBluetooth,
                    .allowBluetoothA2DP
                ]
            )

            AppLogger.shared.log(
                "✅ [TTSAudioSessionController] setCategory OK"
            )
        } catch {
            let e = error as NSError

            AppLogger.shared.log(
                "❌ [TTSAudioSessionController] setCategory failed " +
                "domain=\(e.domain), code=\(e.code), error=\(error)"
            )

            return false
        }

        do {
            try session.setActive(true)

            AppLogger.shared.log(
                "✅ [TTSAudioSessionController] setActive OK"
            )

            return true
        } catch {
            let e = error as NSError

            AppLogger.shared.log(
                "❌ [TTSAudioSessionController] setActive failed " +
                "domain=\(e.domain), code=\(e.code), error=\(error)"
            )

            return false
        }
    }
}
