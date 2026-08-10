import Foundation
import AVFoundation

public final class ExtTTSService: @unchecked Sendable {
    // Memory leak fix: Track temporary files for explicit cleanup
    private var activeTempFiles: Set<URL> = []
    private let tempFileLock = NSLock()
    
    public init() {}
    
    public func synthesizeData(
        text: String,
        voice: String,
        localPath: String,
        configJson: String
    ) async throws -> Data {
        let maxAttempts = 2
        var attempt = 0

        while true {
            attempt += 1
            do {
                let base64String = try await ExtensionManager.shared.ttsGenerate(
                    localPath: localPath,
                    text: text,
                    voice: voice,
                    configJson: configJson
                )

                try Task.checkCancellation()
                guard let audioData = Data(base64Encoded: base64String.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw NSError(domain: "ExtTTSService", code: -20, userInfo: [NSLocalizedDescriptionKey: "Dữ liệu âm thanh Base64 không hợp lệ"])
                }
                return audioData
            } catch {
                if Task.isCancelled || attempt >= maxAttempts || !isTransient(error) {
                    throw error
                }
                AppLogger.shared.log("⚠️ [ExtTTSService] Thử lại lượt \(attempt)/\(maxAttempts) do lỗi tạm thời: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }
    
    public func synthesize(
        text: String,
        voice: String,
        localPath: String,
        configJson: String,
        targetFormat: AVAudioFormat
    ) async throws -> AVAudioPCMBuffer {
        // 1. Tổng hợp và giải mã dữ liệu âm thanh (retry được sở hữu tại
        // synthesizeData để toàn pipeline không tạo retry lồng nhau).
        let audioData = try await synthesizeData(
            text: text,
            voice: voice,
            localPath: localPath,
            configJson: configJson
        )
        
        // 2. Ghi ra tệp tin tạm với đuôi tệp phù hợp (.wav vs .mp3) theo Magic Bytes
        let tempDir = FileManager.default.temporaryDirectory
        let fileExt: String
        if audioData.count >= 4 && audioData[0] == 0x52 && audioData[1] == 0x49 && audioData[2] == 0x46 && audioData[3] == 0x46 {
            fileExt = "wav"
        } else {
            fileExt = "mp3"
        }
        let tempFileUrl = tempDir.appendingPathComponent(UUID().uuidString + "." + fileExt)
        try audioData.write(to: tempFileUrl)
        
        // Memory leak fix: Register temp file for explicit cleanup (defer doesn't execute on Task cancellation)
        _ = tempFileLock.withLock {
            activeTempFiles.insert(tempFileUrl)
        }
        defer {
            cleanupTempFile(tempFileUrl)
        }
        
        // Memory leak fix: Check for task cancellation before expensive AVAudioFile read
        guard !Task.isCancelled else {
            throw CancellationError()
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
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        
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
            return self.preprocessBufferForExtTTS(buffer)
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

                data[frame] = max(-1.0, min(1.0, sample))
            }
        }
        
        return buffer
    }
    
    // Memory leak fix: Helper methods for temp file lifecycle management
    private func cleanupTempFile(_ url: URL) {
        tempFileLock.lock()
        activeTempFiles.remove(url)
        tempFileLock.unlock()
        try? FileManager.default.removeItem(at: url)
    }
    
    public func cleanupAllTempFiles() {
        tempFileLock.lock()
        let files = Array(activeTempFiles)
        activeTempFiles.removeAll()
        tempFileLock.unlock()
        
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    public func resetRuntime() async {
        await ExtensionManager.shared.resetTTSRuntime()
    }

    private func isTransient(_ error: Error) -> Bool {
        let nsError = error as NSError
        let message = error.localizedDescription.lowercased()
        return nsError.domain == NSURLErrorDomain ||
            nsError.code == 408 ||
            nsError.code == 429 ||
            (500...599).contains(nsError.code) ||
            message.contains("timed out") ||
            message.contains("timeout") ||
            message.contains("temporarily") ||
            message.contains("service unavailable") ||
            message.contains("network")
    }
}
