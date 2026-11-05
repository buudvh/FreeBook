import Foundation
import AVFoundation

public final class TTSAudioSessionController: @unchecked Sendable {
    public init() {}

    public func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)
    }

    /// TTS dừng hẳn: trả phiên âm thanh cho app khác — **trừ khi** phim native còn phát (`VideoNativePlaybackFlag`,
    /// thường là phim tắt tiếng phát cùng TTS). Tắt phiên lúc đó thì KVO `outputVolume` của trình phát im luôn: nút âm
    /// lượng cứng không hiện thanh, không bỏ tắt tiếng phim được nữa. Phim dừng sau đó thì
    /// `VideoPlaybackSession.deactivateAudioSessionIfIdle` (phiên do phim bật) hoặc lượt dừng TTS kế tiếp trả phiên.
    @MainActor
    public func deactivateUnlessVideoPlaying() {
        guard !VideoNativePlaybackFlag.isPlaying else {
            AppLogger.shared.log("🔊 [TTSAudioSessionController] TTS dừng nhưng phim còn phát ⇒ giữ phiên âm thanh")
            return
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    public func configureAudioSession() -> Bool {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: []
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
