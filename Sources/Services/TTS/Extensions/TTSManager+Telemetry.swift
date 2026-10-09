import Foundation

/// Façade đo `[TTSPerf]` — logic nằm ở `TTSAutoAdvancePerfTracker` (đợt 8, 1.3.487). Giữ **nguyên tên và chữ ký**
/// để ~45 chỗ gọi trong `TTSManager.swift` / `+Playback.swift` không phải sửa.
extension TTSManager {
    internal var activeTTSAutoAdvancePerf: TTSAutoAdvancePerfTracker.TTSAutoAdvancePerfContext? {
        autoAdvancePerf.activeTTSAutoAdvancePerf
    }

    /// `speakCurrent` ghi trực tiếp hai mốc này ⇒ forward cả get lẫn set.
    internal var paragraph0SynthesisStartUptime: Double {
        get { autoAdvancePerf.paragraph0SynthesisStartUptime }
        set { autoAdvancePerf.paragraph0SynthesisStartUptime = newValue }
    }

    internal var paragraph0AudioCacheHit: Bool {
        get { autoAdvancePerf.paragraph0AudioCacheHit }
        set { autoAdvancePerf.paragraph0AudioCacheHit = newValue }
    }

    internal func currentParagraph0SynthesisMs(untilUptime: Double? = nil) -> Double {
        autoAdvancePerf.currentParagraph0SynthesisMs(untilUptime: untilUptime)
    }

    internal func finishTTSPrefetchPerfSummary() {
        autoAdvancePerf.finishTTSPrefetchPerfSummary()
    }

    /// Truyền `sessionID`/`playingChapterIndex` **hiện tại** — guard cũ đọc trực tiếp hai giá trị này lúc gọi.
    internal func recordPrefetchResult(sessionID: UUID, chapterIndex: Int, engine: String, index: Int, outcome: String, waitMs: Double = 0) {
        autoAdvancePerf.recordPrefetchResult(
            sessionID: sessionID, chapterIndex: chapterIndex, engine: engine, index: index, outcome: outcome, waitMs: waitMs,
            liveSessionID: self.sessionID, liveChapterIndex: self.playingChapterIndex
        )
    }

    internal func createTTSAutoAdvancePerf(sessionID: UUID, generation: Int, chapterIndex: Int, engine: String) {
        autoAdvancePerf.createTTSAutoAdvancePerf(sessionID: sessionID, generation: generation, chapterIndex: chapterIndex, engine: engine)
    }

    internal func updateTTSAutoAdvanceLoadPerf(sessionID: UUID, generation: Int, chapterIndex: Int, loadMs: Double, origin: String) {
        autoAdvancePerf.updateTTSAutoAdvanceLoadPerf(
            sessionID: sessionID, generation: generation, chapterIndex: chapterIndex, loadMs: loadMs, origin: origin)
    }

    internal func updateTTSAutoAdvanceProcessPerf(sessionID: UUID, generation: Int, chapterIndex: Int, processMs: Double) {
        autoAdvancePerf.updateTTSAutoAdvanceProcessPerf(
            sessionID: sessionID, generation: generation, chapterIndex: chapterIndex, processMs: processMs)
    }

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
        autoAdvancePerf.finishTTSAutoAdvancePerf(
            outcome: outcome, endpoint: endpoint, sessionID: sessionID, generation: generation, chapterIndex: chapterIndex,
            synthesisMs: synthesisMs, playerSetupMs: playerSetupMs, audioCacheHit: audioCacheHit
        )
    }
}
