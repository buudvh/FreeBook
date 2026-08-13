import Foundation

extension TTSManager {
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

    internal func currentParagraph0SynthesisMs(untilUptime: Double? = nil) -> Double {
        guard paragraph0SynthesisStartUptime > 0 && !paragraph0AudioCacheHit else { return 0.0 }
        let end = untilUptime ?? ProcessInfo.processInfo.systemUptime
        return max(0.0, (end - paragraph0SynthesisStartUptime) * 1000)
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
}
