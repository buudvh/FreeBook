import AVFoundation
import Foundation
import Observation
import UIKit

/// Dịch phụ đề cứng bằng OCR (1.3.830): đọc chữ Trung in sẵn ở dải dưới khung phim, dịch VietPhrase, phủ bản dịch lên đúng
/// chỗ chữ gốc (`VideoHardSubtitleOverlay`).
///
/// **Vòng đời** — không sửa `VideoPlaybackSession` (file `+Playback` đã sát 400 dòng):
/// - Lớp phủ của màn xem to gọi `screenDidAppear()` / `screenDidDisappear()` (đếm số màn) ⇒ chỉ chạy khi màn to đang hiện.
/// - Trong lúc đó engine tự KVO `player.currentItem`: item mới ⇒ đọc lại công tắc theo tiện ích, tăng `generation` (kết quả về
///   muộn của item cũ bị bỏ), gắn `AVPlayerItemVideoOutput` vào item mới. `stop()` của session thay item bằng `nil` ⇒ tự gỡ.
/// - Mỗi `tickInterval` (timer ở run loop `.common` để cuộn danh sách tập không làm ngưng): bỏ qua khi đang nhúng trang, không
///   còn màn to (chỉ cửa sổ nhỏ), app ở nền, hoặc đang tạm dừng mà khung đã đọc rồi.
///
/// **Một lượt** (`VideoHardSubtitleFrameJob` trên hàng đợi nền tuần tự, lượt trước chưa xong thì bỏ nhịp): lấy khung → mặt nạ →
/// giống lần Vision trước ⇒ giữ nguyên; rỗng ⇒ coi như không có chữ, trừ khi đã quá `emptyProbeInterval` hoặc item này từng có
/// chữ mà mặt nạ không thấy (chữ màu nhạt) → Vision → `VideoHardSubtitleCueTracker` → dịch ngoài main (đệm theo câu gốc).
///
/// Log `🔤 [VideoOCR]`: bật / tắt, tóm tắt mỗi `summaryInterval` giây (số lượt, số lần Vision, ms trung bình, bỏ qua, số câu);
/// lỗi có `❌`. Không tự giảm nhịp theo nhiệt — đo trên máy rồi mới quyết.
@MainActor
@Observable
final class VideoHardSubtitleEngine {
    static let shared = VideoHardSubtitleEngine()

    /// Bản dịch đang hiện cùng khung chữ gốc để lớp phủ che đúng chỗ.
    struct DisplayedCue: Equatable {
        let text: String
        /// Khung chữ gốc, chuẩn hoá theo cả khung hình, gốc trên-trái.
        let rect: CGRect
        /// Cỡ khung hình (điểm ảnh) — lớp phủ tự tính vùng hình theo kiểu khung đang chọn.
        let frameSize: CGSize
        let lineCount: Int
    }

    private struct Stats {
        var ticks = 0
        var visionRuns = 0
        var visionMilliseconds = 0.0
        var similarSkips = 0
        var emptySkips = 0
        var busySkips = 0
        var cues = 0
    }

    // MARK: - Trạng thái View đọc

    /// Công tắc của tiện ích đang phát (`VideoHardSubtitlePreferenceStore`).
    private(set) var isEnabled = false
    private(set) var displayedCue: DisplayedCue?
    /// Dòng báo ngắn trên khung phim (không đọc được hình, máy không hỗ trợ); tự ẩn sau vài giây.
    private(set) var statusMessage: String?

    // MARK: - Tham số (khởi điểm, chưa thử trên máy)

    static let tickInterval: TimeInterval = 0.5
    /// Mặt nạ rỗng vẫn chạy Vision mỗi ngần này giây (phụ đề màu nhạt dưới ngưỡng sáng).
    static let emptyProbeInterval: TimeInterval = 3
    /// Mặt nạ giống mãi vẫn đọc lại mỗi ngần này giây (lượt đọc trước có thể trượt).
    static let forcedRecheckInterval: TimeInterval = 4
    /// Đang phát mà không lấy được khung quá ngần này giây ⇒ báo một lần.
    static let noFrameWarningInterval: TimeInterval = 5
    static let summaryInterval: TimeInterval = 30
    static let translationCacheLimit = 200

    private static let workQueue = DispatchQueue(label: "com.tangcongcac.video-hard-subtitle", qos: .userInitiated)

    // MARK: - Nội bộ

    @ObservationIgnored private let sampler = VideoHardSubtitleFrameSampler()
    @ObservationIgnored private var tracker = VideoHardSubtitleCueTracker()
    @ObservationIgnored private var screenCount = 0
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isProcessing = false
    @ObservationIgnored private var lastMask: VideoHardSubtitleBrightMask?
    @ObservationIgnored private var lastVisionUptime: TimeInterval = 0
    @ObservationIgnored private var maskMissesText = false
    @ObservationIgnored private var lastProcessedItemSeconds: Double?
    @ObservationIgnored private var lastFrameUptime: TimeInterval = 0
    @ObservationIgnored private var hasWarnedNoFrame = false
    @ObservationIgnored private var hasLoggedFailure = false
    @ObservationIgnored private var isLanguageSupported: Bool?
    @ObservationIgnored private var translations: [String: String] = [:]
    @ObservationIgnored private var translationOrder: [String] = []
    @ObservationIgnored private var translationBookId: String?
    @ObservationIgnored private var stats = Stats()
    @ObservationIgnored private var statsSinceUptime: TimeInterval = 0
    @ObservationIgnored private var statusTask: Task<Void, Never>?

    private init() {}

    private var session: VideoPlaybackSession { .shared }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: - Màn xem

    func screenDidAppear() {
        screenCount += 1
        guard screenCount == 1 else { return }
        itemObservation = session.player.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, _ in
            let owner = self
            Task { @MainActor in owner?.handleItemChange() }
        }
    }

    func screenDidDisappear() {
        screenCount = max(0, screenCount - 1)
        guard screenCount == 0 else { return }
        itemObservation?.invalidate()
        itemObservation = nil
        resetRun(reason: "màn xem đóng")
    }

    // MARK: - Công tắc

    func setEnabled(_ enabled: Bool) {
        VideoHardSubtitlePreferenceStore.setEnabled(enabled, packageId: session.launch?.extensionPackageId)
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        AppLogger.shared.log("🔤 [VideoOCR] \(enabled ? "Bật" : "Tắt") dịch phụ đề cứng (nhớ theo tiện ích)")
        restart()
    }

    // MARK: - Item

    private func handleItemChange() {
        guard screenCount > 0 else { return }
        let enabled = VideoHardSubtitlePreferenceStore.isEnabled(packageId: session.launch?.extensionPackageId)
        if enabled != isEnabled { isEnabled = enabled }
        restart()
    }

    private func restart() {
        resetRun(reason: nil)
        guard isEnabled, screenCount > 0, let item = session.player.currentItem else { return }
        guard languageSupported() else { return }
        let bookId = session.launch?.bookId
        if bookId != translationBookId {
            translationBookId = bookId
            translations = [:]
            translationOrder = []
        }
        sampler.attach(to: item)
        lastFrameUptime = Self.now
        statsSinceUptime = Self.now
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        AppLogger.shared.log("🔤 [VideoOCR] Bắt đầu đọc phụ đề cứng («\(session.bookTitle)»)")
    }

    /// Dừng lượt hiện tại: gỡ output, xoá câu đang hiện, tăng `generation`. `reason` ≠ `nil` ⇒ ghi tóm tắt nếu đang chạy.
    private func resetRun(reason: String?) {
        let wasRunning = tickTimer != nil
        generation += 1
        tickTimer?.invalidate()
        tickTimer = nil
        sampler.detach()
        tracker.reset()
        isProcessing = false
        lastMask = nil
        lastVisionUptime = 0
        maskMissesText = false
        lastProcessedItemSeconds = nil
        hasWarnedNoFrame = false
        hasLoggedFailure = false
        if displayedCue != nil { displayedCue = nil }
        if wasRunning {
            logSummary(reason: reason ?? "đổi item / công tắc")
        }
    }

    private func languageSupported() -> Bool {
        let supported: Bool
        if let cached = isLanguageSupported {
            supported = cached
        } else {
            supported = VideoHardSubtitleRecognizer.supportsChinese()
            isLanguageSupported = supported
            if !supported {
                AppLogger.shared.log("❌ [VideoOCR] Vision trên máy này không nhận được chữ Trung (zh-Hans) ⇒ không dịch phụ đề cứng")
            }
        }
        if !supported { showStatus("Máy chưa hỗ trợ nhận chữ Trung") }
        return supported
    }

    // MARK: - Nhịp

    private func tick() {
        guard !isProcessing else {
            stats.busySkips += 1
            return
        }
        guard session.embedContent == nil,
              session.isFullScreenAttached,
              !session.isInBackground,
              UIApplication.shared.applicationState == .active,
              let item = session.player.currentItem,
              sampler.isAttached(to: item) else { return }
        let isPlaying = session.player.timeControlStatus == .playing
        if !isPlaying, let last = lastProcessedItemSeconds, abs(last - item.currentTime().seconds) < 0.05 { return }

        stats.ticks += 1
        let now = Self.now
        let sinceVision = now - lastVisionUptime
        let allowsSimilarSkip = sinceVision < Self.forcedRecheckInterval
        let allowsEmptySkip = !maskMissesText && sinceVision < Self.emptyProbeInterval
        let previousMask = lastMask
        let sampler = self.sampler
        let runGeneration = generation
        isProcessing = true
        Self.workQueue.async {
            let result = VideoHardSubtitleFrameJob.run(
                sampler: sampler,
                previousMask: previousMask,
                allowsSimilarSkip: allowsSimilarSkip,
                allowsEmptySkip: allowsEmptySkip
            )
            Task { @MainActor in
                VideoHardSubtitleEngine.shared.handle(result, generation: runGeneration, wasPlaying: isPlaying)
            }
        }
        logSummaryIfDue(now: now)
    }

    private func handle(_ result: VideoHardSubtitleFrameJob.Result, generation runGeneration: Int, wasPlaying: Bool) {
        guard runGeneration == generation else { return }
        isProcessing = false
        let now = Self.now
        switch result {
        case .noFrame:
            guard wasPlaying else {
                // Tạm dừng: khung của thời điểm này đã lấy rồi ⇒ đợi tới khi tua / phát tiếp.
                lastProcessedItemSeconds = session.player.currentItem?.currentTime().seconds
                return
            }
            if !hasWarnedNoFrame, now - lastFrameUptime >= Self.noFrameWarningInterval {
                hasWarnedNoFrame = true
                AppLogger.shared.log("❌ [VideoOCR] \(Int(Self.noFrameWarningInterval)) giây không lấy được khung hình (nguồn có DRM / chưa giải mã) — «\(session.bookTitle)»")
                showStatus("Không đọc được hình của nguồn này")
            }
        case .similar(let itemSeconds):
            lastFrameUptime = now
            lastProcessedItemSeconds = itemSeconds
            stats.similarSkips += 1
        case .emptyMask(let mask, let itemSeconds):
            lastFrameUptime = now
            lastProcessedItemSeconds = itemSeconds
            lastMask = mask
            stats.emptySkips += 1
            apply(tracker.accept(nil), frameSize: nil)
        case .recognized(let recognition, let mask, let milliseconds, let itemSeconds, let frameSize):
            lastFrameUptime = now
            lastProcessedItemSeconds = itemSeconds
            lastVisionUptime = now
            lastMask = mask
            stats.visionRuns += 1
            stats.visionMilliseconds += milliseconds
            if recognition != nil, mask?.isNearlyEmpty == true, !maskMissesText {
                maskMissesText = true
                AppLogger.shared.log("🔤 [VideoOCR] Phụ đề không đủ sáng cho bộ lọc ⇒ item này chạy Vision mỗi nhịp")
            }
            apply(tracker.accept(recognition), frameSize: frameSize)
        case .failed(let message):
            if !hasLoggedFailure {
                hasLoggedFailure = true
                AppLogger.shared.log("❌ [VideoOCR] Vision lỗi: \(message)")
            }
        }
    }

    // MARK: - Câu đang hiện

    private func apply(_ change: VideoHardSubtitleCueTracker.Change, frameSize: CGSize?) {
        switch change {
        case .none:
            break
        case .cleared:
            if displayedCue != nil { displayedCue = nil }
        case .moved(let recognition):
            guard let cue = displayedCue else { return }
            displayedCue = DisplayedCue(text: cue.text, rect: recognition.rect, frameSize: frameSize ?? cue.frameSize, lineCount: cue.lineCount)
        case .started(let recognition):
            stats.cues += 1
            translate(recognition, frameSize: frameSize ?? displayedCue?.frameSize ?? .zero)
        }
    }

    private func translate(_ recognition: VideoHardSubtitleRecognizer.Recognition, frameSize: CGSize) {
        if let cached = translations[recognition.text] {
            show(cached, for: recognition, frameSize: frameSize)
            return
        }
        let runGeneration = generation
        let text = recognition.text
        let bookId = session.launch?.bookId
        Task {
            let translated = await Task.detached(priority: .userInitiated) { () -> String in
                // Từng dòng một: `<START>` / `<END>` của rule dịch nhanh là đầu / cuối dòng phụ đề.
                text.split(separator: "\n").map { line in
                    TranslateUtils.translateContent(String(line), bookId: bookId, shouldConvertTraditionalToSimplified: true)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            }.value
            guard runGeneration == generation else { return }
            remember(translated, for: text)
            guard let current = tracker.current, current.text == text else { return }
            show(translated, for: current, frameSize: frameSize)
        }
    }

    private func show(_ translated: String, for recognition: VideoHardSubtitleRecognizer.Recognition, frameSize: CGSize) {
        guard !translated.isEmpty else { return }
        displayedCue = DisplayedCue(text: translated, rect: recognition.rect, frameSize: frameSize, lineCount: recognition.lineCount)
    }

    private func remember(_ translated: String, for text: String) {
        guard translations[text] == nil else { return }
        translations[text] = translated
        translationOrder.append(text)
        if translationOrder.count > Self.translationCacheLimit {
            translations[translationOrder.removeFirst()] = nil
        }
    }

    // MARK: - Báo & log

    private func showStatus(_ message: String) {
        statusMessage = message
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }

    private func logSummaryIfDue(now: TimeInterval) {
        guard now - statsSinceUptime >= Self.summaryInterval else { return }
        logSummary(reason: "định kỳ")
    }

    private func logSummary(reason: String) {
        let seconds = Int((Self.now - statsSinceUptime).rounded())
        if stats.ticks > 0 {
            let average = stats.visionRuns > 0 ? Int((stats.visionMilliseconds / Double(stats.visionRuns)).rounded()) : 0
            AppLogger.shared.log(
                "🔤 [VideoOCR] \(seconds)s (\(reason)): \(stats.ticks) lượt, Vision \(stats.visionRuns) lần (TB \(average) ms), "
                    + "bỏ qua giống \(stats.similarSkips) · rỗng \(stats.emptySkips) · đang bận \(stats.busySkips), \(stats.cues) câu"
            )
        }
        stats = Stats()
        statsSinceUptime = Self.now
    }
}
