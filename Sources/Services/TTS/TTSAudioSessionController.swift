import Foundation
import AVFoundation

public final class TTSAudioSessionController: @unchecked Sendable {
    public init() {}

    public func configureAudioSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth, .allowBluetoothA2DP])
            AppLogger.shared.log("✅ [TTSAudioSessionController] setCategory OK: playback/spokenAudio/[duckOthers, allowBluetooth, allowBluetoothA2DP]") // REMOVE_AFTER_NOWPLAYING_DIAGNOSIS
        } catch {
            let nsError = error as NSError
            AppLogger.shared.log("❌ [TTSAudioSessionController] setCategory FAIL (OSStatus=\(nsError.code)): \(error.localizedDescription)") // REMOVE_AFTER_NOWPLAYING_DIAGNOSIS
            return false
        }
        do {
            try session.setActive(true)
            AppLogger.shared.log("✅ [TTSAudioSessionController] setActive OK") // REMOVE_AFTER_NOWPLAYING_DIAGNOSIS
            return true
        } catch {
            let nsError = error as NSError
            AppLogger.shared.log("❌ [TTSAudioSessionController] setActive FAIL (OSStatus=\(nsError.code)): \(error.localizedDescription)") // REMOVE_AFTER_NOWPLAYING_DIAGNOSIS
            return false
        }
    }
}
