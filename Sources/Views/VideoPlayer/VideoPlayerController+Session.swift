import Foundation
import AVFoundation
import SwiftUI
import UIKit

/// Vòng đời phiên xem: lưu tiến độ (số giây vào `paragraphIndex`), `AVAudioSession`, nhường TTS,
/// `isIdleTimerDisabled` và dọn dẹp khi đóng màn.
extension VideoPlayerController {
    // MARK: - Tiến độ

    /// Ghi qua `ReadingProgressStore.checkpoint` (owner `.reader`) để phim vào tab Lịch sử.
    /// Với video, `paragraphIndex` là **số giây** đã xem.
    func saveProgress(reason: String, seconds overrideSeconds: Int? = nil) {
        guard !isTornDown, let episode = currentEpisode else { return }
        let seconds: Int
        if let overrideSeconds {
            seconds = overrideSeconds
        } else if embedContent != nil {
            seconds = 0
        } else if let pending = pendingResumeSeconds {
            // Item chưa sẵn sàng ⇒ đừng ghi đè giây đã lưu bằng 0.
            seconds = pending
        } else if playerStorage?.currentItem == nil {
            seconds = 0
        } else {
            // Đã hết item (KVO `.paused`, đóng màn, vào nền… đến sau `handlePlayedToEnd`) ⇒ giữ giây đã lưu lúc hết
            // tập, không ghi giây ≈ độ dài phim. Phòng thủ thêm khi đầu phát nằm trong giây cuối của item.
            guard !reachedEndOfItem, !isAtEndOfCurrentItem() else { return }
            seconds = currentPlaybackSeconds()
        }

        lastProgressSaveUptime = ProcessInfo.processInfo.systemUptime
        if let last = lastSavedProgress, last.episode == episode.index, last.seconds == seconds { return }
        lastSavedProgress = (episode: episode.index, seconds: seconds)

        let snapshot = ReadingProgressSnapshot(
            bookId: launch.bookId,
            chapterIndex: episode.index,
            paragraphIndex: seconds,
            chapterTitle: episode.title
        )
        Task {
            do {
                try await ReadingProgressStore.shared.checkpoint(snapshot)
            } catch {
                AppLogger.shared.log("❌ [VideoPlayer] Lỗi lưu tiến độ xem (\(reason)): \(error.localizedDescription)")
            }
        }
    }

    func handleScenePhase(_ newPhase: ScenePhase) {
        guard newPhase == .background else { return }
        saveProgress(reason: "vào nền")
    }

    /// `onDisappear` cũng chạy khi `AVPlayerViewController` trình chiếu toàn màn ⇒ khi đó chỉ lưu
    /// tiến độ, không dọn dẹp. Đóng màn thật đi qua nút Quay lại (`teardown()` trước `dismiss`).
    func handleDisappear() {
        if isInSystemFullScreen {
            saveProgress(reason: "vào toàn màn")
            return
        }
        teardown()
    }

    func setSystemFullScreen(_ isFullScreen: Bool) {
        isInSystemFullScreen = isFullScreen
    }

    // MARK: - Đóng màn

    /// Idempotent: nút Quay lại gọi trước `dismiss`, `onDisappear` là lưới an toàn.
    func teardown() {
        guard !isTornDown else { return }
        saveProgress(reason: "đóng màn")
        isTornDown = true

        // Gỡ KVO trước khi pause để không bắn thêm một lượt lưu tiến độ.
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        loadTask?.cancel()
        loadTask = nil
        subtitleTask?.cancel()
        subtitleTask = nil
        resolver?.cancel()
        resolver = nil
        loadGeneration += 1

        // `playerStorage`: đóng màn không được tự dựng `AVPlayer` chưa từng dùng.
        playerStorage?.pause()
        detachCurrentItem()
        if let token = timeObserverToken {
            playerStorage?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        embedContent = nil
        wasPlaying = false

        restoreIdleTimer()
        deactivateAudioSessionIfIdle()
        AppLogger.shared.log("🎬 [VideoPlayer] Đóng màn xem phim (bookId=\(launch.bookId))")
    }

    // MARK: - Âm thanh & TTS

    /// TTS đang đọc thì tạm dừng (chỉ gọi hàm, không observe `TTSManager`), rồi chuyển session sang
    /// `.playback` / `.moviePlayback`. Gọi lại nhiều lần vẫn an toàn.
    func prepareAudioForPlayback() {
        let tts = TTSManager.shared
        if tts.isPlaying {
            AppLogger.shared.log("⏸️ [VideoPlayer] TTS đang đọc ⇒ tạm dừng để phát video")
            tts.pause()
        }

        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .playback || session.mode != .moviePlayback {
                try session.setCategory(.playback, mode: .moviePlayback)
            }
            try session.setActive(true)
            didActivateAudioSession = true
        } catch {
            AppLogger.shared.log("❌ [VideoPlayer] Không cấu hình được AVAudioSession: \(error.localizedDescription)")
        }
    }

    private func deactivateAudioSessionIfIdle() {
        guard didActivateAudioSession else { return }
        didActivateAudioSession = false
        // TTS được bật lại trong lúc xem (widget nổi) thì giữ nguyên session cho nó.
        guard !TTSManager.shared.isPlaying else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            AppLogger.shared.log("❌ [VideoPlayer] Không tắt được AVAudioSession: \(error.localizedDescription)")
        }
    }

    // MARK: - Khoá màn hình

    func setIdleTimerDisabled(_ disabled: Bool) {
        guard !isTornDown || !disabled else { return }
        if idleTimerBaseline == nil {
            idleTimerBaseline = UIApplication.shared.isIdleTimerDisabled
        }
        UIApplication.shared.isIdleTimerDisabled = disabled || (idleTimerBaseline ?? false)
    }

    private func restoreIdleTimer() {
        guard let baseline = idleTimerBaseline else { return }
        UIApplication.shared.isIdleTimerDisabled = baseline
        idleTimerBaseline = nil
    }
}
