import XCTest
@testable import FreeBook

final class NghiTTSPerformanceTests: XCTestCase {
    func testPCM16DurationCalculation() {
        let sampleRate = 22050
        let seconds = 1.5
        let sampleCount = Int(Double(sampleRate) * seconds)
        let samples = [Float](repeating: 0.1, count: sampleCount)
        
        let wavData = WAVEncoder.encodePCM16(samples: samples, sampleRate: sampleRate, channels: 1)
        let calculatedDuration = WAVEncoder.duration(of: wavData)
        
        XCTAssertEqual(calculatedDuration, seconds, accuracy: 0.01)
    }

    func testEffectiveBufferDurationMath() {
        let pcmDuration = 2.0
        let speed = 1.5
        let effectiveDuration = pcmDuration / speed
        XCTAssertEqual(effectiveDuration, 1.333333, accuracy: 0.001)
        
        let startupTarget = 1.2
        XCTAssertGreaterThanOrEqual(effectiveDuration, startupTarget)
    }

    func testThermalStateEvaluation() {
        let nominal = ProcessInfo.ThermalState.nominal
        let fair = ProcessInfo.ThermalState.fair
        let serious = ProcessInfo.ThermalState.serious
        let critical = ProcessInfo.ThermalState.critical
        
        XCTAssertFalse(fair == nominal)
        XCTAssertTrue(fair == .fair || fair == .serious || fair == .critical)
        XCTAssertTrue(serious == .fair || serious == .serious || serious == .critical)
        XCTAssertTrue(critical == .fair || critical == .serious || critical == .critical)
        XCTAssertFalse(nominal == .fair || nominal == .serious || nominal == .critical)
    }

    func testEnergyPolicyShrinksBufferAsTemperatureRises() {
        let nominal = NghiSynthesisPolicy.watermarks(for: .nominal)
        let fair = NghiSynthesisPolicy.watermarks(for: .fair)
        let serious = NghiSynthesisPolicy.watermarks(for: .serious)

        XCTAssertGreaterThan(nominal.high, fair.high)
        XCTAssertGreaterThan(fair.high, serious.high)
        XCTAssertEqual(serious.high, 0)
    }

    func testEnergyPolicyStopsSpeculativeWorkAtSeriousThermalState() {
        XCTAssertTrue(NghiSynthesisPolicy.allowsSpeculativeRefill(at: .nominal))
        XCTAssertTrue(NghiSynthesisPolicy.allowsSpeculativeRefill(at: .fair))
        XCTAssertFalse(NghiSynthesisPolicy.allowsSpeculativeRefill(at: .serious))
        XCTAssertFalse(NghiSynthesisPolicy.allowsSpeculativeRefill(at: .critical))
    }

    func testNextChapterAudioRequiresNominalThermalState() {
        XCTAssertTrue(NghiSynthesisPolicy.allowsNextChapterAudio(at: .nominal))
        XCTAssertFalse(NghiSynthesisPolicy.allowsNextChapterAudio(at: .fair))
        XCTAssertFalse(NghiSynthesisPolicy.allowsNextChapterAudio(at: .serious))
    }

    func testFairThermalStateUsesLongerCooldown() {
        let nominal = NghiSynthesisPolicy.refillCooldownMilliseconds(
            for: .nominal,
            configuredDelay: 500
        )
        let fair = NghiSynthesisPolicy.refillCooldownMilliseconds(
            for: .fair,
            configuredDelay: 500
        )

        XCTAssertEqual(nominal, 750)
        XCTAssertEqual(fair, 1_500)
    }

    func testSelectNghiOptionalRefillCandidatePreventsRangeTrapAtEndOfChapter() {
        // Incident 1: N = 263, count = 264 -> optionalStart = 265 > 264
        let target263 = TTSManager.selectNghiOptionalRefillCandidate(
            currentParagraphIndex: 263,
            paragraphsCount: 264,
            preloadedIndices: [263]
        )
        XCTAssertNil(target263, "Must return nil and not trap when N=263, count=264")

        // Incident 2: N = 83, count = 84 -> optionalStart = 85 > 84
        let target83 = TTSManager.selectNghiOptionalRefillCandidate(
            currentParagraphIndex: 83,
            paragraphsCount: 84,
            preloadedIndices: [83]
        )
        XCTAssertNil(target83, "Must return nil and not trap when N=83, count=84")

        // Boundary case: N = count - 1 (e.g. N=9, count=10)
        let targetCountMinus1 = TTSManager.selectNghiOptionalRefillCandidate(
            currentParagraphIndex: 9,
            paragraphsCount: 10,
            preloadedIndices: [9]
        )
        XCTAssertNil(targetCountMinus1, "Must return nil when N = count - 1")

        // Boundary case: N = count - 2 (e.g. N=8, count=10)
        let targetCountMinus2 = TTSManager.selectNghiOptionalRefillCandidate(
            currentParagraphIndex: 8,
            paragraphsCount: 10,
            preloadedIndices: [8, 9]
        )
        XCTAssertNil(targetCountMinus2, "Must return nil when N = count - 2")

        // Valid ordinary optional range selection
        let validTarget = TTSManager.selectNghiOptionalRefillCandidate(
            currentParagraphIndex: 10,
            paragraphsCount: 50,
            preloadedIndices: [10, 11]
        )
        XCTAssertEqual(validTarget, 12, "Should select optional reserve index 12 when 11 is in preloadedIndices")

        // Skipping already preloaded optional candidates
        let skipTarget = TTSManager.selectNghiOptionalRefillCandidate(
            currentParagraphIndex: 10,
            paragraphsCount: 50,
            preloadedIndices: [10, 11, 12, 13]
        )
        XCTAssertEqual(skipTarget, 14, "Should skip preloaded indices 12 and 13 to select 14")
    }

    func testPiperTTSServiceSilenceSpecAndUnspeakableCheck() {
        XCTAssertTrue(PiperTTSService.isUnspeakable(""))
        XCTAssertTrue(PiperTTSService.isUnspeakable("   "))
        XCTAssertTrue(PiperTTSService.isUnspeakable("!!! ??? ..."))

        XCTAssertFalse(PiperTTSService.isUnspeakable("Chương 126"))
        XCTAssertFalse(PiperTTSService.isUnspeakable("123"))

        let specShort = PiperTTSService.makeSilenceSpec(text: "Dòng ngắn,", speed: 1.0, phrasePause: 0.15, sentencePause: 0.3)
        XCTAssertGreaterThan(specShort.samples.count, 0)
        XCTAssertEqual(specShort.sampleRate, 22050)
        XCTAssertGreaterThan(specShort.pcmDuration, 0)

        let specSentence = PiperTTSService.makeSilenceSpec(text: "Câu dài.", speed: 1.0, phrasePause: 0.15, sentencePause: 0.3)
        XCTAssertGreaterThan(specSentence.pcmDuration, specShort.pcmDuration)
    }

    func testClassifyTTSErrorExhaustive() {
        let (r1, nr1) = TTSManager.classifyTTSError(TTSError.badRequest("bad"))
        XCTAssertEqual(r1, "badRequest")
        XCTAssertTrue(nr1)

        let (r2, nr2) = TTSManager.classifyTTSError(TTSError.notFound("not found"))
        XCTAssertEqual(r2, "notFound")
        XCTAssertTrue(nr2)

        let (r3, nr3) = TTSManager.classifyTTSError(TTSError.modelNotCached("cached"))
        XCTAssertEqual(r3, "modelNotCached")
        XCTAssertTrue(nr3)

        let (r4, nr4) = TTSManager.classifyTTSError(TTSError.engineUnavailable("unavailable"))
        XCTAssertEqual(r4, "engineUnavailable")
        XCTAssertTrue(nr4)

        let (r5, nr5) = TTSManager.classifyTTSError(TTSError.internalError("internal"))
        XCTAssertEqual(r5, "internalError")
        XCTAssertFalse(nr5)

        let (r6, nr6) = TTSManager.classifyTTSError(NSError(domain: "test", code: 1))
        XCTAssertEqual(r6, "unknownError")
        XCTAssertFalse(nr6)
    }

    func testPiperTTSServiceSilenceStreamingPayload() {
        let streamingSilence = PiperTTSService.buildSilenceStreamingPayload(text: "Tiền xử lý rỗng.", speed: 1.0, phrasePause: 0.15, sentencePause: 0.3)
        XCTAssertEqual(streamingSilence.chunkPayload.chunkIndex, 0)
        XCTAssertEqual(streamingSilence.chunkPayload.totalChunks, 1)
        XCTAssertTrue(streamingSilence.chunkPayload.isLast)
        XCTAssertEqual(streamingSilence.chunkPayload.sampleRate, 22050)
        XCTAssertTrue(streamingSilence.chunkPayload.samples.allSatisfy { $0 == 0.0 })
        XCTAssertGreaterThan(streamingSilence.wavData.count, 44)
    }

    func testEvaluateRefillErrorPolicy() {
        // First retryable failure -> retryScheduled with attempt 1
        let (s1, o1) = TTSManager.evaluateRefillError(TTSError.internalError("retry1"), currentAttempts: 0)
        XCTAssertEqual(s1.attempts, 1)
        XCTAssertFalse(s1.isBlocked)
        XCTAssertEqual(o1, .retryScheduled(reason: "internalError", attempt: 1))

        // Second retryable failure -> blocked with attempt 2
        let (s2, o2) = TTSManager.evaluateRefillError(TTSError.internalError("retry2"), currentAttempts: 1)
        XCTAssertEqual(s2.attempts, 2)
        XCTAssertTrue(s2.isBlocked)
        XCTAssertEqual(o2, .blocked(reason: "internalError", action: "blocked_max_retries"))

        // Non-retryable errors -> blocked immediately
        let (s3, o3) = TTSManager.evaluateRefillError(TTSError.modelNotCached("cached"), currentAttempts: 0)
        XCTAssertTrue(s3.isBlocked)
        XCTAssertEqual(o3, .blocked(reason: "modelNotCached", action: "blocked_non_retryable"))

        let (s4, o4) = TTSManager.evaluateRefillError(TTSError.engineUnavailable("unavailable"), currentAttempts: 0)
        XCTAssertTrue(s4.isBlocked)
        XCTAssertEqual(o4, .blocked(reason: "engineUnavailable", action: "blocked_non_retryable"))

        let (s5, o5) = TTSManager.evaluateRefillError(TTSError.badRequest("bad"), currentAttempts: 0)
        XCTAssertTrue(s5.isBlocked)
        XCTAssertEqual(o5, .blocked(reason: "badRequest", action: "blocked_non_retryable"))

        let (s6, o6) = TTSManager.evaluateRefillError(TTSError.notFound("not found"), currentAttempts: 0)
        XCTAssertTrue(s6.isBlocked)
        XCTAssertEqual(o6, .blocked(reason: "notFound", action: "blocked_non_retryable"))

        // CancellationError -> ignored
        let (sCancel, oCancel) = TTSManager.evaluateRefillError(CancellationError(), currentAttempts: 1)
        XCTAssertEqual(sCancel.attempts, 1)
        XCTAssertFalse(sCancel.isBlocked)
        XCTAssertEqual(oCancel, .cancelled)
    }

    func testRefillSelectionSkipsBlockedIndexAndSelectsLaterOptional() {
        let selected = TTSManager.selectNghiOptionalRefillCandidate(
            currentParagraphIndex: 0,
            paragraphsCount: 10,
            preloadedIndices: [0, 1],
            blockedIndices: [2]
        )
        XCTAssertEqual(selected, 3, "Must skip blocked index 2 and select optional index 3")
    }

    func testRefillFailureKeySessionIdentity() {
        let sessionA = UUID()
        let sessionB = UUID()
        let keyA = TTSManager.RefillFailureKey(sessionID: sessionA, chapterIndex: 126, paragraphIndex: 1)
        let keyA2 = TTSManager.RefillFailureKey(sessionID: sessionA, chapterIndex: 126, paragraphIndex: 1)
        let keyB = TTSManager.RefillFailureKey(sessionID: sessionB, chapterIndex: 126, paragraphIndex: 1)

        XCTAssertEqual(keyA, keyA2)
        XCTAssertNotEqual(keyA, keyB)
    }

    func testCanScheduleNghiRefillGate() {
        XCTAssertTrue(TTSManager.canScheduleNghiRefill(hasRefillTask: false, hasRetryTask: false))
        XCTAssertFalse(TTSManager.canScheduleNghiRefill(hasRefillTask: true, hasRetryTask: false))
        XCTAssertFalse(TTSManager.canScheduleNghiRefill(hasRefillTask: false, hasRetryTask: true))
        XCTAssertFalse(TTSManager.canScheduleNghiRefill(hasRefillTask: true, hasRetryTask: true))
    }
}
