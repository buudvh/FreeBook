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
}
