import Foundation
import AVFoundation
import Observation
import UIKit

/// Tầng **màn hình** của trình phát — trạng thái chỉ sống khi màn đang hiện: ẩn/hiện điều khiển (tự ẩn 4 giây), khoá
/// cảm ứng, toàn màn ở màn dọc, khoá xoay, Vừa/Lấp đầy/Phóng, xem trước khi tua, HUD cử chỉ, bảng danh sách tập.
///
/// Phát / nạp / tiến độ / PiP thuộc `VideoPlaybackSession` (sống lâu hơn màn hình) — controller chỉ gọi hàm của session.
@MainActor
@Observable
final class VideoPlayerController {
    enum Gravity: String, CaseIterable, Identifiable {
        case fit
        case fill
        case zoom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fit: return "Vừa"
            case .fill: return "Lấp đầy"
            case .zoom: return "Phóng"
            }
        }

        var layerGravity: AVLayerVideoGravity {
            switch self {
            case .fit: return .resizeAspect
            case .fill: return .resize
            case .zoom: return .resizeAspectFill
            }
        }
    }

    enum Feedback: Equatable {
        case seek(target: Double, delta: Double)
        case doubleTap(forward: Bool, seconds: Int)
        case brightness(Double)
        case volume(Double)
        case boost
    }

    let session: VideoPlaybackSession
    var controlsVisible = true
    var isTouchLocked = false
    var isPortraitFullscreen = false
    var isOrientationLocked = false
    var showsEpisodePanel = false
    /// Sheet "Tải nhiều tập…" (menu `⋯`) — `VideoPlayerScreen` trình bày `TaskOptionsSheet`.
    var showsBatchDownloadSheet = false
    var gravity: Gravity = .fit
    /// Giây đang xem trước khi kéo thanh tua / vuốt ngang; `nil` = không tua.
    var scrubSeconds: Double?
    var feedback: Feedback?

    /// Màn hình gắn: vuốt xuống ở khung dọc ⇒ thu nhỏ.
    @ObservationIgnored var onMinimizeRequest: (() -> Void)?
    @ObservationIgnored private var autoHideTask: Task<Void, Never>?
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?
    @ObservationIgnored private var tapStreak: (forward: Bool, until: TimeInterval, seconds: Int)?
    @ObservationIgnored private var scrubOrigin: Double = 0

    init(session: VideoPlaybackSession) {
        self.session = session
    }

    // MARK: - Ẩn / hiện điều khiển

    func showControls() {
        controlsVisible = true
        scheduleAutoHide()
    }

    func toggleControls() {
        if controlsVisible {
            autoHideTask?.cancel()
            controlsVisible = false
        } else {
            showControls()
        }
    }

    /// Chỉ tự ẩn khi đang phát và không có thao tác dở (tua, bảng tập).
    func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, let self else { return }
            guard self.session.isPlaying, self.scrubSeconds == nil, !self.showsEpisodePanel else { return }
            self.controlsVisible = false
        }
    }

    func setTouchLocked(_ locked: Bool) {
        isTouchLocked = locked
        showsEpisodePanel = false
        showControls()
    }

    func setEpisodePanelVisible(_ visible: Bool) {
        showsEpisodePanel = visible
        if visible {
            autoHideTask?.cancel()
        } else {
            scheduleAutoHide()
        }
    }

    func setGravity(_ newValue: Gravity) {
        gravity = newValue
        showControls()
    }

    func togglePortraitFullscreen() {
        isPortraitFullscreen.toggle()
        showControls()
    }

    func toggleOrientationLock() {
        isOrientationLocked.toggle()
        VideoOrientationLock.setLocked(isOrientationLocked)
        showControls()
    }

    /// Nút Xoay: dọc ⇒ ngang toàn màn ngay; ngang ⇒ về dọc.
    func rotate(currentlyLandscape: Bool) {
        if currentlyLandscape { isPortraitFullscreen = false }
        VideoOrientationLock.rotate(toLandscape: !currentlyLandscape)
        showControls()
    }

    // MARK: - Chạm

    func handleSingleTap(side: VideoGestureView.Side) {
        if !isTouchLocked, continueTapStreak(side: side) { return }
        if showsEpisodePanel {
            setEpisodePanelVisible(false)
            return
        }
        toggleControls()
    }

    /// Lùi/tới 10 giây; chạm tiếp trong 0,9 giây cùng phía thì cộng dồn.
    func handleDoubleTap(side: VideoGestureView.Side) {
        guard !isTouchLocked, session.hasPlayableItem else { return }
        let forward = side == .trailing
        let now = ProcessInfo.processInfo.systemUptime
        var seconds = 10
        if let streak = tapStreak, streak.forward == forward, now < streak.until {
            seconds = streak.seconds + 10
        }
        tapStreak = (forward: forward, until: now + 0.9, seconds: seconds)
        session.seek(by: forward ? 10 : -10)
        showFeedback(.doubleTap(forward: forward, seconds: seconds), duration: 0.9)
    }

    private func continueTapStreak(side: VideoGestureView.Side) -> Bool {
        guard let streak = tapStreak,
              ProcessInfo.processInfo.systemUptime < streak.until,
              streak.forward == (side == .trailing) else { return false }
        handleDoubleTap(side: side)
        return true
    }

    // MARK: - Vuốt

    /// Tua / độ sáng / âm lượng: ẩn **cả** lớp điều khiển (kiểu YouTube, người dùng chốt 2026-10-24) để HUD không đè
    /// lên timeline và cụm nút giữa; nhả tay vẫn ẩn, chạm để hiện lại.
    func handlePanBegan(_ kind: VideoGestureView.PanKind) {
        if kind != .dismiss {
            autoHideTask?.cancel()
            controlsVisible = false
        }
        // Vuốt chỉnh âm lượng = muốn nghe ⇒ bỏ tắt tiếng. Bật tiếng khi video đang phát sẽ dừng TTS đang đọc
        // (đúng hành vi của `setMuted(false)`). Chỉ cử chỉ vuốt, không theo dõi nút âm lượng cứng.
        if kind == .volume, session.isMuted {
            session.setMuted(false)
        }
        guard kind == .seek, session.hasPlayableItem else { return }
        scrubOrigin = session.currentPlaybackTime
        scrubSeconds = scrubOrigin
    }

    func handlePanChanged(_ kind: VideoGestureView.PanKind, value: CGFloat) {
        switch kind {
        case .seek:
            guard scrubSeconds != nil else { return }
            let target = clampedSeconds(scrubOrigin + Double(value) * seekSpan)
            scrubSeconds = target
            showFeedback(.seek(target: target, delta: target - scrubOrigin), duration: nil)
        case .brightness:
            showFeedback(.brightness(Double(value)), duration: 0.8)
        case .volume:
            showFeedback(.volume(Double(value)), duration: 0.8)
        case .dismiss:
            break
        }
    }

    func handlePanEnded(_ kind: VideoGestureView.PanKind, value: CGFloat) {
        switch kind {
        case .seek:
            guard let target = scrubSeconds else { return }
            scrubSeconds = nil
            session.seek(to: target)
            showFeedback(feedback ?? .seek(target: target, delta: 0), duration: 0.5)
            scheduleAutoHide()
        case .dismiss:
            if value > 80 { onMinimizeRequest?() }
        case .brightness, .volume:
            break
        }
    }

    func handleLongPress(_ active: Bool) {
        guard !isTouchLocked else { return }
        if active {
            guard session.hasPlayableItem, session.isPlaying else { return }
            session.setTemporaryBoost(true)
            showFeedback(.boost, duration: nil)
        } else {
            session.setTemporaryBoost(false)
            if feedback == .boost { feedback = nil }
        }
    }

    /// Vuốt hết bề ngang = 90 giây (phim ngắn hơn thì bằng độ dài phim).
    private var seekSpan: Double {
        let duration = session.durationSeconds
        return duration > 0 ? min(90, duration) : 90
    }

    private func clampedSeconds(_ seconds: Double) -> Double {
        let duration = session.durationSeconds
        let upper = duration > 0 ? duration : max(seconds, 0)
        return min(max(0, seconds), upper)
    }

    // MARK: - Thanh tua

    func beginScrub() {
        guard session.hasPlayableItem else { return }
        autoHideTask?.cancel()
        scrubSeconds = session.currentPlaybackTime
    }

    func updateScrub(fraction: Double) {
        guard scrubSeconds != nil, session.durationSeconds > 0 else { return }
        scrubSeconds = clampedSeconds(fraction * session.durationSeconds)
    }

    func endScrub() {
        guard let target = scrubSeconds else { return }
        scrubSeconds = nil
        session.seek(to: target)
        scheduleAutoHide()
    }

    // MARK: - HUD cử chỉ

    func showFeedback(_ newValue: Feedback, duration: Double?) {
        feedback = newValue
        feedbackTask?.cancel()
        guard let duration else { return }
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.feedback = nil
        }
    }

    /// Màn biến mất: huỷ các task hẹn giờ.
    func cancelTimers() {
        autoHideTask?.cancel()
        feedbackTask?.cancel()
    }
}
