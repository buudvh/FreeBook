import Foundation
import Observation

/// Hẹn giờ tắt của trình phát phim (`VideoPlaybackSession.sleepTimer`) và trình nghe nhạc
/// (`AudioPlaybackSession.sleepTimer`) — cùng luật với hẹn giờ của TTS (`TTSManager.SleepTimerMode`):
/// - Mốc phút (`minutes`): **chỉ đếm khi đang phát** (`updatePlaybackState`); tạm dừng giữ số giây còn lại, phát lại thì
///   đếm tiếp. Hết giờ ⇒ chủ phiên tạm dừng (`onExpire`) + báo "Hẹn giờ: đã tạm dừng"; chế độ **giữ nguyên** (như TTS):
///   lần phát sau bắt đầu lại một vòng đủ.
/// - "Hết tập" / "Hết bài" (`endOfItem`): item đang phát hết thì dừng ở đó — phiên hỏi `stopsAfterItemEnded()` **trước**
///   mọi nhánh tự sang item kế (tập kế, phim đề xuất, bài kế, lặp). Chế độ cũng giữ nguyên tới khi người dùng tắt.
///
/// Mỗi phiên một bộ đếm, gắn với **lượt đang phát**: phiên `stop()` (đóng hẳn, mở phim / album khác) gọi `reset()`. Đếm
/// theo mốc `systemUptime` (không cộng dồn từng tick) nên tick trễ lúc app ở nền / đang cuộn không làm lệch giờ; `Timer`
/// gắn `RunLoop.main` chế độ `.common` — nhạc / phim phát nền thì tiến trình vẫn chạy nên vẫn đếm.
///
/// Không SwiftUI, không `ToastManager`: lời báo đi qua `MediaPresentationEventCenter`. View chỉ đọc; số giây đổi mỗi giây
/// nên chỉ view lá nhỏ được đọc `badgeText` / `compactBadgeText` / `remainingSeconds`.
@MainActor
@Observable
final class MediaSleepTimer {
    enum Mode: Equatable {
        case off
        case minutes(Int)
        /// Hết tập (phim) / hết bài (nhạc).
        case endOfItem
    }

    /// Trình phát sở hữu bộ đếm — chỉ khác chữ hiển thị và nhãn log.
    enum Medium {
        case video
        case audio

        /// Nhãn ô cuối của lưới mốc.
        var endOfItemTitle: String {
            switch self {
            case .video: return "Hết tập"
            case .audio: return "Hết bài"
            }
        }

        var endOfItemIcon: String {
            switch self {
            case .video: return "film"
            case .audio: return "music.note"
            }
        }

        var noun: String {
            switch self {
            case .video: return "phim"
            case .audio: return "nhạc"
            }
        }

        var logTag: String {
            switch self {
            case .video: return "[VideoSleepTimer]"
            case .audio: return "[AudioSleepTimer]"
            }
        }
    }

    /// Chế độ + số giây còn lại — giữ hẹn giờ qua lượt tự sang phim đề xuất (`VideoPlaybackSession.open`).
    struct Schedule: Equatable {
        let mode: Mode
        let remainingSeconds: Int
    }

    let medium: Medium
    private(set) var mode: Mode = .off
    /// Giây còn lại của mốc phút; giữ khi tạm dừng. `0` = chưa hẹn / đã hết giờ (lần phát sau bắt đầu vòng mới).
    private(set) var remainingSeconds = 0

    /// Hết giờ ⇒ chủ phiên tạm dừng bằng `pause()` của chính phiên (không `player.pause()` trần).
    @ObservationIgnored var onExpire: (() -> Void)?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var deadlineUptime: TimeInterval = 0
    /// Trạng thái phát lần báo gần nhất — chỉ xử lý lúc chuyển (phát ⇄ dừng).
    @ObservationIgnored private var isPlaybackActive = false

    init(medium: Medium) {
        self.medium = medium
    }

    // MARK: - Trạng thái suy ra

    var isActive: Bool { mode != .off }

    var stopsAtEndOfItem: Bool { mode == .endOfItem }

    /// Mốc phút đang chọn; `nil` khi không hẹn theo phút.
    var selectedMinutes: Int? {
        if case .minutes(let minutes) = mode { return minutes }
        return nil
    }

    /// Tóm tắt **chỉ theo chế độ** (không đổi mỗi giây) — chữ phụ của hàng ngăn kéo.
    var modeSummary: String? {
        switch mode {
        case .off: return nil
        case .minutes(let minutes): return "\(minutes) phút"
        case .endOfItem: return medium.endOfItemTitle
        }
    }

    /// Như badge TTS: "m:ss" khi còn giây (kể cả lúc tạm dừng), "N phút" khi đã hết giờ (phát lại là vòng mới), nhãn ô cuối
    /// khi hẹn hết tập / hết bài, rỗng khi tắt.
    var badgeText: String {
        switch mode {
        case .off:
            return ""
        case .minutes(let minutes):
            guard remainingSeconds > 0 else { return "\(minutes) phút" }
            return String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
        case .endOfItem:
            return medium.endOfItemTitle
        }
    }

    /// Bản gọn cho badge nhỏ trên thanh trình phát: số phút còn lại (làm tròn lên) + "p".
    var compactBadgeText: String {
        switch mode {
        case .off:
            return ""
        case .minutes(let minutes):
            guard remainingSeconds > 0 else { return "\(minutes)p" }
            return "\((remainingSeconds + 59) / 60)p"
        case .endOfItem:
            return medium.endOfItemTitle
        }
    }

    var schedule: Schedule { Schedule(mode: mode, remainingSeconds: remainingSeconds) }

    // MARK: - Người dùng chọn

    func start(minutes: Int) {
        guard minutes > 0 else {
            cancel()
            return
        }
        stopTicking()
        mode = .minutes(minutes)
        remainingSeconds = minutes * 60
        AppLogger.shared.log("⏱️ \(medium.logTag) Hẹn \(minutes) phút (đang phát: \(isPlaybackActive ? "có" : "không"))")
        if isPlaybackActive { startTicking() }
    }

    func setStopAtEndOfItem() {
        stopTicking()
        mode = .endOfItem
        remainingSeconds = 0
        AppLogger.shared.log("⏱️ \(medium.logTag) Hẹn dừng khi \(medium.endOfItemTitle.lowercased())")
    }

    func cancel() {
        guard isActive || ticker != nil else { return }
        stopTicking()
        mode = .off
        remainingSeconds = 0
        AppLogger.shared.log("⏱️ \(medium.logTag) Tắt hẹn giờ")
    }

    // MARK: - Phiên gọi

    /// Phiên dừng hẳn / mở phim, album khác ⇒ huỷ hẹn giờ của lượt cũ.
    func reset() {
        cancel()
        isPlaybackActive = false
    }

    /// Giữ hẹn giờ qua lượt tự sang phim đề xuất: gọi **sau** `reset()` của lượt cũ (chưa phát nên chưa đếm).
    func restore(_ schedule: Schedule) {
        guard schedule.mode != .off else { return }
        stopTicking()
        mode = schedule.mode
        remainingSeconds = schedule.remainingSeconds
        AppLogger.shared.log("⏱️ \(medium.logTag) Giữ hẹn giờ cho phim tự sang (còn \(schedule.remainingSeconds) giây)")
        if isPlaybackActive { beginCountingIfNeeded() }
    }

    /// Gọi lặp an toàn ở mỗi lần trạng thái phát có thể đổi; chỉ lúc chuyển mới bắt đầu / dừng đếm.
    func updatePlaybackState(isPlaying: Bool) {
        guard isPlaying != isPlaybackActive else { return }
        isPlaybackActive = isPlaying
        if isPlaying {
            beginCountingIfNeeded()
        } else {
            pauseCounting()
        }
    }

    /// Item vừa phát hết: hẹn "Hết tập" / "Hết bài" ⇒ báo và trả `true` — phiên dừng ở đây, không sang item kế.
    func stopsAfterItemEnded() -> Bool {
        guard mode == .endOfItem else { return false }
        AppLogger.shared.log("⏱️ \(medium.logTag) \(medium.endOfItemTitle) ⇒ dừng, không sang mục kế")
        MediaPresentationEventCenter.shared.send(.showToast(
            message: "⏱️ Hẹn giờ: đã dừng \(medium.noun) khi \(medium.endOfItemTitle.lowercased()).",
            type: .info
        ))
        return true
    }

    // MARK: - Đếm

    /// Hết giờ rồi phát lại ⇒ vòng mới đủ số phút (như `TTSManager.restartSleepTimerIfNeeded`).
    private func beginCountingIfNeeded() {
        guard case .minutes(let minutes) = mode, ticker == nil else { return }
        if remainingSeconds <= 0 { remainingSeconds = minutes * 60 }
        startTicking()
    }

    private func pauseCounting() {
        guard ticker != nil else { return }
        let left = secondsUntilDeadline()
        stopTicking()
        remainingSeconds = left
        if left == 0 { expire() }
    }

    private func startTicking() {
        stopTicking()
        guard remainingSeconds > 0 else { return }
        deadlineUptime = ProcessInfo.processInfo.systemUptime + Double(remainingSeconds)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func secondsUntilDeadline() -> Int {
        let left = deadlineUptime - ProcessInfo.processInfo.systemUptime
        return left > 0 ? Int(left.rounded(.up)) : 0
    }

    private func tick() {
        guard ticker != nil else { return }
        let left = secondsUntilDeadline()
        if left != remainingSeconds { remainingSeconds = left }
        guard left == 0 else { return }
        stopTicking()
        expire()
    }

    private func expire() {
        guard case .minutes(let minutes) = mode else { return }
        remainingSeconds = 0
        AppLogger.shared.log("⏱️ \(medium.logTag) Hết \(minutes) phút ⇒ tạm dừng \(medium.noun)")
        onExpire?()
        MediaPresentationEventCenter.shared.send(.showToast(
            message: "⏱️ Hẹn giờ (\(minutes) phút): đã tạm dừng \(medium.noun).",
            type: .info
        ))
    }
}
