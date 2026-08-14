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
}
