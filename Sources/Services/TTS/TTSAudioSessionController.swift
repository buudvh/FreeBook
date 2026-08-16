import Foundation
import AVFoundation

public final class TTSAudioSessionController: @unchecked Sendable {
    public init() {}

    public func configureAudioSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            return true
        } catch {
            let nsError = error as NSError
            AppLogger.shared.log("❌ [TTSAudioSessionController] Lỗi cấu hình AVAudioSession (OSStatus=\(nsError.code)): \(error.localizedDescription)")
            return false
        }
    }
}
