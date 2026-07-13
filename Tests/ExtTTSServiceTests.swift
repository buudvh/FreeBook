import XCTest
import AVFoundation
@testable import FreeBook

final class ExtTTSServiceTests: XCTestCase {
    func testExtTTSPreprocessingCapsPeakAmplitude() {
        let service = ExtTTSService()
        let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8)!
        buffer.frameLength = 8

        guard let channelData = buffer.floatChannelData else {
            XCTFail("Expected float channel data")
            return
        }

        channelData[0][0] = 0.0
        channelData[0][1] = 0.95
        channelData[0][2] = -1.0
        channelData[0][3] = 0.2
        channelData[0][4] = 0.0
        channelData[0][5] = 0.8
        channelData[0][6] = -0.7
        channelData[0][7] = 0.6

        let processed = service.preprocessBufferForExtTTS(buffer)
        guard let processedData = processed.floatChannelData else {
            XCTFail("Expected processed float channel data")
            return
        }

        var maxAmplitude: Float = 0
        for frame in 0..<Int(processed.frameLength) {
            maxAmplitude = max(maxAmplitude, abs(processedData[0][frame]))
        }

        XCTAssertLessThanOrEqual(maxAmplitude, 0.85)
    }
}
