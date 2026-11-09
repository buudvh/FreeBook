import Foundation
import AVFoundation

/// Xử lý đoạn TTS remote (Google / tiện ích) phát hỏng giữa chừng — xem `TTSPlaybackFailureTracker` cho lý do và luật.
extension TTSManager {
    /// `audioPlayerDecodeErrorDidOccur` (đã về main actor). Player cũ (đã bị thay / dừng) vẫn có thể bắn lỗi cho buffer
    /// đang giải mã ⇒ gỡ delegate cho im hẳn, không xử lý lại. Player đang phát ⇒ ghi **một** dòng `❌` đủ để biết engine,
    /// đoạn và dữ liệu lỗi (không ghi nội dung chương), dừng hẳn player rồi phục hồi.
    func handleRemoteDecodeError(_ player: AVAudioPlayer, error: Error?) {
        guard audioPlayer === player else {
            player.delegate = nil
            player.stop()
            return
        }
        AppLogger.shared.log(
            "❌ [TTSRemote] Lỗi giải mã khi phát: engine=\(tool) chương=\(playingChapterIndex) đoạn=\(currentParagraphIndex) "
                + "id=\(currentPlaybackId ?? "-") \(Self.describeFailedPlayer(player, error: error))"
        )
        stopCurrentHardwarePlayer()
        recoverFromRemotePlaybackFailure(reason: "lỗi giải mã")
    }

    /// Đoạn remote đang phát hỏng (player đã dừng): bỏ dữ liệu đệm của đoạn — dữ liệu hỏng mà còn đó thì `speakCurrent`
    /// phát lại đúng nó — rồi thử lại một lần / bỏ qua / dừng theo `playbackFailureTracker`. Người dùng đã dừng trước đó
    /// ⇒ chỉ cập nhật màn khoá.
    func recoverFromRemotePlaybackFailure(reason: String) {
        let index = currentParagraphIndex
        preloadedData.removeValue(forKey: index)
        preloadedDurations.removeValue(forKey: index)
        currentPlaybackId = nil
        guard isPlaying, index >= 0, index < paragraphs.count else {
            updateNowPlayingInfo()
            return
        }

        let key = TTSPlaybackFailureTracker.ParagraphKey(
            sessionID: sessionID,
            chapterIndex: playingChapterIndex,
            paragraphIndex: index
        )
        switch playbackFailureTracker.recordRemoteFailure(key) {
        case .retry:
            AppLogger.shared.log("❌ [TTSRemote] Đoạn \(index) (chương \(playingChapterIndex)) \(reason) ⇒ tổng hợp lại một lần")
            speakCurrent()
        case .skip:
            AppLogger.shared.log("❌ [TTSRemote] Đoạn \(index) (chương \(playingChapterIndex)) vẫn \(reason) ⇒ bỏ qua, đọc tiếp")
            skipForward()
        case .stop:
            AppLogger.shared.log(
                "❌ [TTSRemote] \(TTSPlaybackFailureTracker.maxConsecutiveSkippedParagraphs) đoạn liền \(reason) ⇒ dừng đọc"
            )
            pause()
            TTSPresentationEventCenter.shared.send(.showToast(
                message: "Âm thanh TTS bị lỗi liên tục, đã tạm dừng đọc.",
                type: .error
            ))
        }
    }

    /// Số byte, 8 byte đầu, định dạng và vị trí của player lỗi + domain/mã lỗi — không chứa nội dung chương.
    static func describeFailedPlayer(_ player: AVAudioPlayer, error: Error?) -> String {
        let data = player.data
        let head = data.map { bytes in
            bytes.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        } ?? "-"
        let format = player.format
        let errorText: String
        if let error {
            let nsError = error as NSError
            errorText = "\(nsError.domain)#\(nsError.code)"
        } else {
            errorText = "-"
        }
        return "bytes=\(data?.count ?? -1) đầu=[\(head)] sr=\(Int(format.sampleRate)) kênh=\(format.channelCount) "
            + String(format: "dài=%.2fs đang=%.2fs ", player.duration, player.currentTime)
            + "lỗi=\(errorText)"
    }
}
