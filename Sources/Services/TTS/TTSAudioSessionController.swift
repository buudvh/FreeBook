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
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
            return true
        } catch {
            AppLogger.shared.log("❌ [TTSAudioSessionController] Lỗi cấu hình AVAudioSession: \(error.localizedDescription)")
            return false
        }
    }
}
