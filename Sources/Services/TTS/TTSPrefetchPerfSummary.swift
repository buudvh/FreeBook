import Foundation

public struct TTSPrefetchPerfSummary: Sendable {
    public var sessionID: UUID
    public var chapterIndex: Int
    public var engine: String
    public var immediateHit: Int
    public var waitedHit: Int
    public var miss: Int
    public var failure: Int
    public var retrySuccess: Int
    public var retryFailure: Int
    public var totalWaitMs: Double
    public var maxWaitMs: Double
    public var startTime: Date

    public init(
        sessionID: UUID,
        chapterIndex: Int,
        engine: String,
        immediateHit: Int = 0,
        waitedHit: Int = 0,
        miss: Int = 0,
        failure: Int = 0,
        retrySuccess: Int = 0,
        retryFailure: Int = 0,
        totalWaitMs: Double = 0,
        maxWaitMs: Double = 0,
        startTime: Date = Date()
    ) {
        self.sessionID = sessionID
        self.chapterIndex = chapterIndex
        self.engine = engine
        self.immediateHit = immediateHit
        self.waitedHit = waitedHit
        self.miss = miss
        self.failure = failure
        self.retrySuccess = retrySuccess
        self.retryFailure = retryFailure
        self.totalWaitMs = totalWaitMs
        self.maxWaitMs = maxWaitMs
        self.startTime = startTime
    }
}
