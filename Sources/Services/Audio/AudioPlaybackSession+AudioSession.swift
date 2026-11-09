import Foundation
import AVFoundation

/// `AVAudioSession` và phân xử ba bên (nhạc / TTS / phim). Tại một thời điểm **một** bên giữ màn khoá; nhạc và TTS **không
/// bao giờ cùng phát** (không bao giờ cùng lúc có thanh nhạc mini lẫn widget TTS):
/// - Người dùng chọn phát nhạc (mở album, chọn bài, bấm phát, thử lại) ⇒ `beginUserRequestedPlayback`: TTS có phiên
///   (đang đọc hoặc widget còn hiện) thì **tắt hẳn** như bấm ✕ của widget (`stopTTSForMusic`), phim nhường
///   (`VideoNowPlayingCoordinator.yieldToOtherMedia`: tạm dừng + trả phiên; phim tắt tiếng phát tiếp).
/// - Nhạc thật sự phát (`readyToPlay` tự phát — kể cả tự sang bài —, `play()`, chuyển sang `.playing` từ màn khoá / tai
///   nghe) ⇒ `prepareAudioForPlayback`: như trên, cấu hình `.playback` / `.default`, rồi `AudioNowPlayingCoordinator.claim()`
///   **sau** khi bên kia đã trả phiên.
/// - TTS bắt đầu / tiếp tục đọc (`TTSManager+NowPlaying` ⇒ `AudioNowPlayingCoordinator.yieldToTTS`) ⇒ `stopForTTS`: trình
///   nghe **dừng hẳn** (lưu tiến độ, thanh mini + hub ẩn), không dựng lại TTS, không tắt `AVAudioSession`.
/// - Phim giành âm thanh (`VideoPlaybackSession.prepareAudioForPlayback`) ⇒ `pauseForOtherMedia`: nhạc tạm dừng, bài đang
///   nạp không tự phát, coordinator trả phiên (không dựng lại TTS).
/// - Đóng hẳn (`stop`) / bài lỗi ⇒ trả phiên + dựng lại TTS (`release(handBackToTTS: true)`); tắt `AVAudioSession` chỉ khi
///   TTS và phim native đều không phát.
extension AudioPlaybackSession {
    /// Người dùng chủ động chọn phát nhạc: bỏ cờ nhường, tắt hẳn TTS / cho phim nhường ngay để bài tự phát khi sẵn sàng.
    /// Tự sang bài kế khi hết bài **không** đi qua đây — vẫn tôn trọng cờ nhường (phim).
    func beginUserRequestedPlayback() {
        autoplayBlockedByOtherMedia = false
        stopTTSForMusic(reason: "Người dùng chọn nghe nhạc")
        VideoNowPlayingCoordinator.shared.yieldToOtherMedia()
    }

    /// Nhạc bắt đầu phát: tắt hẳn TTS / cho phim nhường (nếu còn), cấu hình phiên âm thanh rồi giữ màn khoá. Gọi lặp an toàn.
    func prepareAudioForPlayback() {
        // TRƯỚC `setActive(true)` + `claim()`: `TTSManager.stop` xoá Now Playing và có thể tắt `AVAudioSession` (khi
        // `AudioPlaybackFlag` còn `false` — lối `readyToPlay`).
        stopTTSForMusic(reason: "Nhạc bắt đầu phát")
        // Phim nhường (trả phiên) TRƯỚC khi nhạc giữ phiên: `release` của phim tắt lệnh tua, chạy sau `claim` là mất nút.
        VideoNowPlayingCoordinator.shared.yieldToOtherMedia()

        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .playback || session.mode != .default {
                try session.setCategory(.playback, mode: .default)
            }
            try session.setActive(true)
            didActivateAudioSession = true
        } catch {
            AppLogger.shared.log("❌ [AudioPlayer] Không cấu hình được AVAudioSession: \(error.localizedDescription)")
        }
        // TTS `stop()` ở trên vừa xoá Now Playing ⇒ giành phiên SAU đó để không bị ghi đè.
        AudioNowPlayingCoordinator.shared.claim()
        publishNowPlaying()
    }

    /// Tắt hẳn TTS như bấm ✕ của widget (`TTSManager.stop`: lưu tiến độ đọc, ẩn widget, xoá Now Playing) — chỉ khi TTS
    /// thật sự có phiên (đang đọc hoặc widget còn hiện). Không gọi ngược vào trình nghe (`stop` của TTS không đi qua
    /// `setSystemNowPlayingPlaybackState(.playing)`).
    private func stopTTSForMusic(reason: String) {
        let tts = TTSManager.shared
        guard tts.isPlaying || tts.showFloatingWidget else { return }
        AppLogger.shared.log("⏹️ [AudioPlayer] \(reason) ⇒ tắt hẳn TTS (đang đọc: \(tts.isPlaying ? "có" : "không"))")
        tts.stop()
    }

    /// TTS bắt đầu / tiếp tục đọc (`AudioNowPlayingCoordinator.yieldToTTS`, coordinator đã trả phiên trước) ⇒ dừng hẳn
    /// trình nghe như `stop()` — lưu tiến độ, gỡ item, thanh mini + hub ẩn (`AudioMiniPlayerState.isActive = false`) — trừ
    /// hai điểm: không dựng lại lệnh / Now Playing của TTS (TTS đang tự cấu hình, gọi lại là đệ quy vào
    /// `setRemoteCommandsEnabled`) và không tắt `AVAudioSession` (TTS vừa cấu hình). Không có album ⇒ không làm gì (hook
    /// chạy ở mọi lượt TTS bắt đầu / tiếp tục đọc).
    func stopForTTS() {
        guard isActive else { return }
        AppLogger.shared.log("⏹️ [AudioPlayer] TTS bắt đầu đọc ⇒ dừng hẳn trình nghe (bookId=\(bookId))")
        stopSession(handingOverToTTS: true)
    }

    /// Phim giành âm thanh (`AudioNowPlayingCoordinator.yieldToOtherMedia`). Cờ đặt TRƯỚC mọi guard: bài đang nạp xong
    /// (`readyToPlay`) không được tự phát chồng.
    func pauseForOtherMedia() {
        guard isActive else { return }
        autoplayBlockedByOtherMedia = true
        guard player.timeControlStatus != .paused else { return }
        AppLogger.shared.log("⏸️ [AudioPlayer] Phim giành âm thanh ⇒ tạm dừng nhạc")
        player.pause()
    }

    /// Trả `AVAudioSession` khi đóng hẳn trình nghe — chỉ khi chính trình nghe đã bật và TTS / phim native đều không phát.
    func deactivateAudioSessionIfIdle() {
        guard didActivateAudioSession else { return }
        didActivateAudioSession = false
        guard !TTSManager.shared.isPlaying, !VideoNativePlaybackFlag.isPlaying else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            AppLogger.shared.log("❌ [AudioPlayer] Không tắt được AVAudioSession: \(error.localizedDescription)")
        }
    }

    // MARK: - Ngắt (cuộc gọi, báo thức…)

    /// `.began` ⇒ nhớ có đang phát không (KVO dừng có thể tới trước thông báo — nhìn thêm lần dừng ≤ 1,5 s trước) rồi dừng;
    /// `.ended` + `shouldResume` + trước đó đang phát + nhạc còn giữ màn khoá ⇒ phát tiếp. Nhạc không giữ màn khoá (TTS /
    /// phim đang giữ) thì bỏ qua — ngắt đó không phải của nhạc.
    func handleAudioInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard isActive, let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        let holdsSession = AudioNowPlayingCoordinator.shared.isHoldingSession
        switch type {
        case .began:
            guard holdsSession else { return }
            let pausedJustNow = ProcessInfo.processInfo.systemUptime - lastPauseUptime <= 1.5
            wasPlayingBeforeInterruption = isPlaying || pausedJustNow
            if player.timeControlStatus != .paused { player.pause() }
            AppLogger.shared.log("📞 [AudioPlayer] Bị ngắt âm thanh ⇒ dừng nhạc (đang phát trước đó: \(wasPlayingBeforeInterruption ? "có" : "không"))")
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            let shouldResume = wasPlayingBeforeInterruption && options.contains(.shouldResume)
            wasPlayingBeforeInterruption = false
            guard shouldResume, holdsSession, !autoplayBlockedByOtherMedia, !TTSManager.shared.isPlaying else { return }
            AppLogger.shared.log("📞 [AudioPlayer] Hết ngắt âm thanh ⇒ phát tiếp")
            play()
        @unknown default:
            break
        }
    }
}
