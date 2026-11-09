import Foundation
import AVFoundation
import UIKit

/// Tiến độ nghe + vòng đời app.
///
/// - Ghi qua `ReadingProgressStore.checkpoint` (owner `.reader`) để album vào tab Lịch sử: `chapterIndex` = chỉ số bài
///   (mục lục), `paragraphIndex` = **số giây** (như phim). Lúc: bắt đầu phát, tạm dừng, đổi bài, mỗi ~10 s khi phát, vào
///   nền, đóng trình nghe. Chỉ ghi khi `Book` đã có (`isBookReady`) — `persist` bỏ qua khi chưa có `Book` mà mốc chống
///   ghi trùng lại chặn lần ghi sau.
/// - Rời app: nhạc phát tiếp (app có background audio cho TTS — `UIBackgroundModes: audio` ở `project.yml`); chỉ lưu tiến độ.
/// - Ngắt âm thanh (cuộc gọi…): `+AudioSession.handleAudioInterruption`.
extension AudioPlaybackSession {
    func saveProgress(reason: String, seconds overrideSeconds: Int? = nil) {
        guard isActive, isBookReady, !bookId.isEmpty, let index = currentTrackIndex, let track = self.track(at: index) else { return }
        let seconds: Int
        if let overrideSeconds {
            seconds = overrideSeconds
        } else if let pending = pendingResumeSeconds {
            // Item chưa sẵn sàng ⇒ đừng ghi đè giây đã lưu bằng 0.
            seconds = pending
        } else if player.currentItem == nil {
            seconds = 0
        } else {
            // Đã hết bài (KVO `.paused` tới sau `didPlayToEnd`) ⇒ giữ giây đã lưu lúc hết bài.
            guard !reachedEndOfItem, !isAtEndOfCurrentItem() else { return }
            seconds = Int(currentPlaybackTime)
        }

        lastProgressSaveUptime = ProcessInfo.processInfo.systemUptime
        if let last = lastSavedProgress, last.track == index, last.seconds == seconds { return }
        lastSavedProgress = (track: index, seconds: seconds)

        let snapshot = ReadingProgressSnapshot(
            bookId: bookId,
            chapterIndex: index,
            paragraphIndex: seconds,
            chapterTitle: track.title
        )
        Task {
            do {
                try await ReadingProgressStore.shared.checkpoint(snapshot)
            } catch {
                AppLogger.shared.log("❌ [AudioPlayer] Lỗi lưu tiến độ nghe (\(reason)): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Vòng đời app

    func installLifecycleObservers() {
        guard lifecycleTokens.isEmpty else { return }
        let center = NotificationCenter.default
        let background = center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveProgress(reason: "vào nền")
            }
        }
        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            // Đọc userInfo trước khi vào main actor (`Notification` không mang qua ranh giới isolation).
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleAudioInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
            }
        }
        lifecycleTokens = [background, interruption]
    }
}
