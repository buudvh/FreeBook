import AVFoundation
import Foundation

/// Dọn phát nền trước khi chuyển sang LiveContainer (nút "Mở LiveContainer" của `AppUpdateSheet`, 1.3.824).
///
/// Lý do (anh Bửu: bấm "Mở LiveContainer" lúc đang nghe truyện / nhạc thì app chỉ tắt, không mở lại LiveContainer):
/// LiveContainer chuyển app bằng `LCSharedUtils.launchToGuestAppWithClassicMode` — xin `LSApplicationWorkspace` mở lại
/// chính nó **hai lần**, lần trả lời đầu thì tự `SIGKILL`, trông vào yêu cầu thứ hai để iOS dựng app lên lại. Khi app
/// đang giữ phiên âm thanh nền, iOS còn coi tiến trình là "đang chạy" lúc nhận yêu cầu thứ hai ⇒ coi như đã mở xong ⇒ app
/// chết mà không ai mở lại (suy từ mã LiveContainer + triệu chứng, chưa thử máy).
///
/// Nên trước khi gửi `livecontainer://livecontainer-launch?bundle-name=ui`: dừng hẳn TTS, nhạc, phim đang có, tắt
/// `AVAudioSession`, chờ ~0,4 s cho iOS ghi nhận app hết phát nền. Không có gì đang phát ⇒ trả ngay, không chờ.
/// Hệ quả đã nêu trong plan: anh bấm Huỷ ở hộp xác nhận của LiveContainer thì việc nghe vẫn đã dừng.
@MainActor
enum LiveContainerSwitchPreparer {
    private static let settleDelay: Duration = .milliseconds(400)

    static func prepare() async {
        var stopped: [String] = []

        let tts = TTSManager.shared
        if tts.isPlaying || tts.showFloatingWidget {
            tts.stop()
            stopped.append("TTS")
        }
        // Chỉ chạm `AudioPlaybackSession.shared` khi có album (chạm là dựng `AVPlayer`).
        if AudioMiniPlayerState.shared.isActive {
            AudioPlaybackSession.shared.stop()
            stopped.append("nhạc")
        }
        // Như trên: chỉ chạm `VideoPlaybackSession.shared` khi có phim.
        if VideoMiniPlayerState.shared.isActive || VideoNativePlaybackFlag.isPlaying {
            VideoPlaybackSession.shared.stop()
            stopped.append("phim")
        }

        guard !stopped.isEmpty else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            AppLogger.shared.log("❌ [AppUpdate] Không tắt được phiên âm thanh trước khi mở LiveContainer: \(error.localizedDescription)")
        }
        AppLogger.shared.log("📲 [AppUpdate] Dừng \(stopped.joined(separator: ", ")) trước khi mở LiveContainer")
        try? await Task.sleep(for: settleDelay)
    }
}
