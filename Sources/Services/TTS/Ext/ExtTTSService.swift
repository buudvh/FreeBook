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
        return buffer
    }
}
