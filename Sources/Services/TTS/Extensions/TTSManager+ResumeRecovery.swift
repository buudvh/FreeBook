import AVFoundation
import Foundation

/// Phát tiếp sau tạm dừng (1.3.1026, anh Bửu: "để pause truyện lâu bấm start bằng sheet mini thì không phát lại, phải bấm
/// tai nghe mới được"). Nút tai nghe của Reader (trang đã cuộn khỏi đoạn đang dừng) dừng hẳn phiên rồi dựng phiên mới ⇒
/// bật lại phiên âm thanh từ đầu; nút ⏯ của sheet nghe mini / màn khoá chỉ `resume()` phiên cũ. Hai chỗ hỏng của đường
/// `resume()`:
/// - **Phiên âm thanh không được bật lại.** `configureAudioSession()` tin cờ `isAudioSessionConfigured`, mà trong lúc tạm
///   dừng phiên có thể đã bị tắt mà cờ vẫn `true`: app khác phát tiếng (ngắt lúc TTS không phát ⇒ trước đây không hạ cờ),
///   phim trong app trả phiên khi rảnh, nghe thử giọng ở Cài đặt TTS (`setActive(false)`), cuộc gọi. Tạm dừng càng lâu càng
///   dễ dính ⇒ mỗi lần phát tiếp **luôn** cấu hình + bật lại phiên (nhẹ: `setCategory` + `setActive`).
/// - **VieNeu / NghiTTS không kiểm tiếng có chạy thật.** `AVAudioPlayer.play()` có thể trả `true` mà thời gian đứng yên
///   (đã gặp ở đường Google / tiện ích — `verifyRemoteResumeProgress`), đường `NghiAudioPlayerQueue` thì không có bước
///   kiểm ⇒ kẹt "đang phát" không tiếng. Nay kiểm sau 0,25 s, không tiến ⇒ đọc lại đoạn hiện tại từ đầu đoạn.
extension TTSManager {
    /// Gọi ở `resume()` (đường tạm dừng → phát) thay cho `configureAudioSession()`.
    internal func reactivateAudioSessionForResume() {
        isAudioSessionConfigured = false
        configureAudioSession()
        AppLogger.shared.log(
            "🔊 [TTSResume] Phát tiếp (\(tool)) — bật lại phiên âm thanh: \(isAudioSessionConfigured ? "OK" : "lỗi")"
        )
    }

    /// VieNeu / NghiTTS: `NghiAudioPlayerQueue.resume()` đã trả `true` ⇒ báo đang phát rồi kiểm tiếng có chạy thật.
    internal func didResumeNghiPlayer() {
        publishLifecycleState(isPlaying: true)
        guard let player = nghiAudioPlayerQueue.currentPlayer else { return }
        verifyNghiResumeProgress(player: player, positionBeforePlay: player.currentTime)
    }

    /// Cùng khuôn `verifyRemoteResumeProgress`: sau 0,25 s mà `currentTime` không tiến (player vẫn là cái vừa phát tiếp,
    /// phiên còn đang phát) ⇒ dừng player hỏng, bật lại phiên, đọc lại đoạn hiện tại (như đổi tai nghe giữa chừng —
    /// `handleRouteChange`). Đoạn đã nạp sẵn tiếng thì `speakCurrent` phát ngay, chưa có thì tổng hợp lại.
    private func verifyNghiResumeProgress(player: AVAudioPlayer, positionBeforePlay: TimeInterval) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, self.isPlaying, TTSManager.isLocalEngine(self.tool) else { return }
            guard self.nghiAudioPlayerQueue.currentPlayer === player else { return }
            guard player.currentTime <= positionBeforePlay else { return }
            AppLogger.shared.log(
                "⚠️ [TTSResume] \(self.tool): play() trả true nhưng currentTime đứng ở \(String(format: "%.2f", positionBeforePlay))s — đọc lại đoạn \(self.currentParagraphIndex)"
            )
            let index = self.currentParagraphIndex
            self.stopCurrentPlayback()
            self.reactivateAudioSessionForResume()
            self.currentParagraphIndex = index
            self.speakCurrent()
        }
    }
}
