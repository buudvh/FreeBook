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
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetoothA2DP])
            try session.setActive(true)
            return true
        } catch {
            let nsError = error as NSError
            AppLogger.shared.log("❌ [TTSAudioSessionController] Lỗi cấu hình AVAudioSession (OSStatus=\(nsError.code)): \(error.localizedDescription)")
            return false
        }
    }
}
