import Foundation

/// Đo `[TTSPerf]` của luồng nghe: chuyển chương (`AutoAdvance`), tổng kết nạp trước (`PrefetchSummary`,
/// `SlowPrefetch`) và khoảng lặng bàn giao của engine remote (`RemoteHandoff`). Tách khỏi `TTSManager`
/// (đợt 8 tách god object, 1.3.487) — **chỉ ghi log**, không quyết định gì về phát.
///
/// Thân hàm chuyển **nguyên văn**; khác duy nhất: `recordPrefetchResult` nhận `liveSessionID`/`liveChapterIndex`
/// do façade truyền **lúc gọi** (trước đây đọc `self.sessionID`/`self.playingChapterIndex`) — không chụp sẵn.
@MainActor
final class TTSAutoAdvancePerfTracker {
    internal struct TTSAutoAdvancePerfContext {
        let sessionID: UUID
        let generation: Int
        let chapterIndex: Int
        let engine: String
        let startUptime: Double
        var origin: String = "unknown"
        var loadMs: Double = 0
        var processMs: Double = 0
        var synthesisMs: Double = 0
        var playerSetupMs: Double = 0
        var audioCacheHit: Bool = false
        var isFinished: Bool = false
    }

    internal private(set) var activeTTSAutoAdvancePerf: TTSAutoAdvancePerfContext? = nil
    private var activePrefetchPerfSummary: TTSPrefetchPerfSummary? = nil
    internal var paragraph0SynthesisStartUptime: Double = 0
    internal var paragraph0AudioCacheHit: Bool = false

    internal func resetParagraph0Timing() {
        paragraph0SynthesisStartUptime = 0
        paragraph0AudioCacheHit = false
    }

    internal func currentParagraph0SynthesisMs(untilUptime: Double? = nil) -> Double {
        guard paragraph0SynthesisStartUptime > 0 && !paragraph0AudioCacheHit else { return 0.0 }
        let end = untilUptime ?? ProcessInfo.processInfo.systemUptime
        return max(0.0, (end - paragraph0SynthesisStartUptime) * 1000)
    }

    @MainActor
    internal func finishTTSPrefetchPerfSummary() {
        guard let summary = activePrefetchPerfSummary else { return }
        activePrefetchPerfSummary = nil
        let total = summary.immediateHit + summary.waitedHit + summary.miss + summary.failure
        guard total > 0, AppLogger.shared.isLoggingEnabled else { return }
        let logLine = String(
            format: "[TTSPerf] PrefetchSummary chapter=%d engine=%@ immediateHit=%d waitedHit=%d miss=%d failure=%d retrySuccess=%d retryFailure=%d totalWaitMs=%.2f maxWaitMs=%.2f",
            summary.chapterIndex,
            summary.engine,
            summary.immediateHit,
            summary.waitedHit,
            summary.miss,
            summary.failure,
            summary.retrySuccess,
            summary.retryFailure,
            summary.totalWaitMs,
            summary.maxWaitMs
        )
        AppLogger.shared.log(logLine)
    }

    @MainActor
    internal func recordPrefetchResult(
        sessionID: UUID, chapterIndex: Int, engine: String, index: Int, outcome: String, waitMs: Double = 0,
        liveSessionID: UUID, liveChapterIndex: Int
    ) {
        guard AppLogger.shared.isLoggingEnabled else { return }
        guard sessionID == liveSessionID, chapterIndex == liveChapterIndex else { return }
        ensurePrefetchPerfSummary(sessionID: sessionID, chapterIndex: chapterIndex, engine: engine)
        guard var summary = activePrefetchPerfSummary,
              summary.sessionID == sessionID,
              summary.chapterIndex == chapterIndex,
              summary.engine == engine else { return }

        switch outcome {
        case "hit":
            summary.immediateHit += 1
        case "hit_wait":
            summary.waitedHit += 1
            summary.totalWaitMs += waitMs
            summary.maxWaitMs = max(summary.maxWaitMs, waitMs)
            if waitMs >= 100.0 {
                AppLogger.shared.log(String(format: "[TTSPerf] SlowPrefetch chapter=%d index=%d engine=%@ waitMs=%.2f", summary.chapterIndex, index, summary.engine, waitMs))
            }
        case "miss":
            summary.miss += 1
        case "failure":
            summary.failure += 1
            summary.totalWaitMs += waitMs
            summary.maxWaitMs = max(summary.maxWaitMs, waitMs)
        default:
            break
        }
        activePrefetchPerfSummary = summary
    }

    @MainActor
    internal func createTTSAutoAdvancePerf(
        sessionID: UUID,
        generation: Int,
        chapterIndex: Int,
        engine: String
    ) {
        finishTTSAutoAdvancePerf(outcome: "superseded", endpoint: "superseded")
        ensurePrefetchPerfSummary(sessionID: sessionID, chapterIndex: chapterIndex, engine: engine)
        resetParagraph0Timing()
        guard AppLogger.shared.isLoggingEnabled else { return }
        activeTTSAutoAdvancePerf = TTSAutoAdvancePerfContext(
            sessionID: sessionID,
            generation: generation,
            chapterIndex: chapterIndex,
            engine: engine,
            startUptime: ProcessInfo.processInfo.systemUptime
        )
    }

    @MainActor
    internal func updateTTSAutoAdvanceLoadPerf(
        sessionID: UUID,
        generation: Int,
        chapterIndex: Int,
        loadMs: Double,
        origin: String
    ) {
        guard var ctx = activeTTSAutoAdvancePerf,
              !ctx.isFinished,
              ctx.sessionID == sessionID,
              ctx.generation == generation,
              ctx.chapterIndex == chapterIndex else { return }
        ctx.loadMs = loadMs
        ctx.origin = origin
        activeTTSAutoAdvancePerf = ctx
    }

    @MainActor
    internal func updateTTSAutoAdvanceProcessPerf(
        sessionID: UUID,
        generation: Int,
        chapterIndex: Int,
        processMs: Double
    ) {
        guard var ctx = activeTTSAutoAdvancePerf,
              !ctx.isFinished,
              ctx.sessionID == sessionID,
              ctx.generation == generation,
              ctx.chapterIndex == chapterIndex else { return }
        ctx.processMs = processMs
        activeTTSAutoAdvancePerf = ctx
    }

    @MainActor
    internal func finishTTSAutoAdvancePerf(
        outcome: String,
        endpoint: String,
        sessionID: UUID? = nil,
        generation: Int? = nil,
        chapterIndex: Int? = nil,
        synthesisMs: Double = 0,
        playerSetupMs: Double = 0,
        audioCacheHit: Bool? = nil
    ) {
        guard var ctx = activeTTSAutoAdvancePerf, !ctx.isFinished else { return }
        if let sID = sessionID, ctx.sessionID != sID { return }
        if let gen = generation, ctx.generation != gen { return }
        if let chIdx = chapterIndex, ctx.chapterIndex != chIdx { return }

        ctx.isFinished = true
        activeTTSAutoAdvancePerf = nil

        let endUptime = ProcessInfo.processInfo.systemUptime
        let totalMs = (endUptime - ctx.startUptime) * 1000

        let finalSynMs = synthesisMs > 0 ? synthesisMs : ctx.synthesisMs
        let finalSetupMs = playerSetupMs > 0 ? playerSetupMs : ctx.playerSetupMs
        let finalCacheHit = audioCacheHit ?? ctx.audioCacheHit

        resetParagraph0Timing()

        let logLine = String(
            format: "[TTSPerf] AutoAdvance chapter=%d engine=%@ origin=%@ loadMs=%.2f processMs=%.2f synthesisMs=%.2f playerSetupMs=%.2f totalMs=%.2f cacheHit=%@ outcome=%@ endpoint=%@",
            ctx.chapterIndex,
            ctx.engine,
            ctx.origin,
            ctx.loadMs,
            ctx.processMs,
            finalSynMs,
            finalSetupMs,
            totalMs,
            finalCacheHit ? "true" : "false",
            outcome,
            endpoint
        )
        AppLogger.shared.log(logLine)
    }



    @MainActor
    internal func ensurePrefetchPerfSummary(sessionID: UUID, chapterIndex: Int, engine: String) {
        guard AppLogger.shared.isLoggingEnabled else {
            if activePrefetchPerfSummary != nil {
                activePrefetchPerfSummary = nil
            }
            return
        }
        if let current = activePrefetchPerfSummary {
            if current.sessionID == sessionID && current.chapterIndex == chapterIndex && current.engine == engine {
                return
            }
            finishTTSPrefetchPerfSummary()
        }
        activePrefetchPerfSummary = TTSPrefetchPerfSummary(
            sessionID: sessionID,
            chapterIndex: chapterIndex,
            engine: engine
        )
    }

    var lastRemoteAudioFinishUptime: Double = 0

    // MARK: - Đo khoảng lặng giữa hai đoạn (engine remote)

    /// Log khoảng lặng giữa hai đoạn của engine **remote** (`google`/ext).
    ///
    /// Local đã có mốc tương ứng — log `🔊 [TTSPerf] NghiHandoff` phát khi bàn giao giữa hai đoạn trong
    /// `NghiAudioPlayerQueue`, nơi `nextPlayer` đã `prepareToPlay()` sẵn. Remote **không** dựng sẵn
    /// player cho đoạn kế, nên gap ở đây gồm cả chi phí tạo + `prepareToPlay` một `AVAudioPlayer` mới.
    ///
    /// Con số này là **cơ sở để quyết định** có làm `prepareNext` cho remote hay không: nếu gap thật
    /// nhỏ thì việc thêm machinery là tối ưu thứ không đáng. Xem plan §6.3.
    internal func logRemoteHandoffGap(playStartUptime: Double, paragraphIndex: Int, engine: String) {
        guard AppLogger.shared.isLoggingEnabled, lastRemoteAudioFinishUptime > 0 else { return }
        let gapMs = (playStartUptime - lastRemoteAudioFinishUptime) * 1000
        AppLogger.shared.log(String(
            format: "[TTSPerf] RemoteHandoff engine=%@ index=%d gapMs=%.2f",
            engine,
            paragraphIndex,
            gapMs
        ))
    }
}
