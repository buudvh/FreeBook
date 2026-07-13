import Foundation
import AVFoundation

public final class ExtTTSService {
    public init() {}
    
    public func synthesize(
        text: String,
        voice: String,
        localPath: String,
        configJson: String,
        targetFormat: AVAudioFormat
    ) async throws -> AVAudioPCMBuffer {
        // 1. Gọi JS để tạo base64 audio
        let base64String = try await ExtensionManager.shared.ttsGenerate(
            localPath: localPath,
            text: text,
            voice: voice,
            configJson: configJson
        )
        
        guard let audioData = Data(base64Encoded: base64String.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NSError(domain: "ExtTTSService", code: -20, userInfo: [NSLocalizedDescriptionKey: "Dữ liệu âm thanh Base64 không hợp lệ"])
        }
        
        // 2. Ghi ra tệp tin tạm
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileUrl = tempDir.appendingPathComponent(UUID().uuidString + ".mp3")
        try audioData.write(to: tempFileUrl)
        
        // Khối dọn dẹp tệp tin tạm
        defer {
            try? FileManager.default.removeItem(at: tempFileUrl)
        }
        
        // 3. Đọc bằng AVAudioFile và chuyển sang PCMBuffer
        let audioFile = try AVAudioFile(forReading: tempFileUrl)
        let fileFormat = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        
        guard frameCount > 0 else {
            throw NSError(domain: "ExtTTSService", code: -21, userInfo: [NSLocalizedDescriptionKey: "Tệp âm thanh trống sau khi giải mã"])
        }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: frameCount) else {
            throw NSError(domain: "ExtTTSService", code: -22, userInfo: [NSLocalizedDescriptionKey: "Không thể khởi tạo AVAudioPCMBuffer"])
        }
        
        try audioFile.read(into: buffer)
        
        // Nếu fileFormat trùng khớp với targetFormat, trả về trực tiếp
        if fileFormat == targetFormat {
            return preprocessBufferForExtTTS(buffer)
        }
        
        // Chuyển đổi sang targetFormat bằng AVAudioConverter
        guard let converter = AVAudioConverter(from: fileFormat, to: targetFormat) else {
            AppLogger.shared.log("❌ [ExtTTSService] Không thể tạo AVAudioConverter từ \(fileFormat) sang \(targetFormat)")
            return preprocessBufferForExtTTS(buffer)
        }
        
        let ratio = targetFormat.sampleRate / fileFormat.sampleRate
        let targetFrameCapacity = AVAudioFrameCount(Double(frameCount) * ratio) + 16
        
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCapacity) else {
            return preprocessBufferForExtTTS(buffer)
        }
        
        var error: NSError? = nil
        var isDataProvided = false
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            if isDataProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            isDataProvided = true
            outStatus.pointee = .haveData
            return preprocessBufferForExtTTS(buffer)
        }
        
        let status = converter.convert(to: targetBuffer, error: &error, withInputFrom: inputBlock)

        guard targetBuffer.frameLength > 0 else {
            AppLogger.shared.log("❌ [ExtTTSService] Convert tạo buffer rỗng")
            return preprocessBufferForExtTTS(buffer)
        }

        if status == .error {
            if let error = error {
                AppLogger.shared.log("❌ [ExtTTSService] Lỗi convert định dạng sang targetFormat: \(error.localizedDescription)")
            }
            return preprocessBufferForExtTTS(buffer)
        }
        
        return preprocessBufferForExtTTS(targetBuffer)
    }
    
    func preprocessBufferForExtTTS(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard buffer.frameLength > 0 else { return buffer }
        guard let channelData = buffer.floatChannelData else { return buffer }
        
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var peakAmplitude: Float = 0
        
        for channel in 0..<channelCount {
            let data = channelData[channel]
            for frame in 0..<frameCount {
                peakAmplitude = max(peakAmplitude, abs(data[frame]))
            }
        }
        
        let targetPeak: Float = 0.85
        let gain: Float
        if peakAmplitude > targetPeak {
            gain = targetPeak / peakAmplitude
        } else {
            gain = 1.0
        }
        
        let fadeFrames = min(frameCount / 10, 220)
        let fadeFramesClamped = max(fadeFrames, 1)
        
        for channel in 0..<channelCount {
            let data = channelData[channel]
            for frame in 0..<frameCount {
                var sample = data[frame] * gain

                if frame < fadeFramesClamped {
                    let t = Float(frame) / Float(fadeFramesClamped)
                    sample *= t
                } else if frame >= frameCount - fadeFramesClamped {
                    let t = Float(frameCount - 1 - frame) / Float(fadeFramesClamped)
                    sample *= max(t, 0)
                }

                data[frame] = sample
            }
        }
        
        return buffer
    }
}
