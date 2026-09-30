import AVFoundation
import Foundation

/// Giải mã + lấy lại mẫu cho **audio mẫu dùng để nhân bản giọng**.
///
/// Đây là chỗ **duy nhất** trong app dùng `AVAudioFile`/`AVAudioConverter` (trước lượt này không có chỗ
/// nào), nên hai quyết định dưới đây được ghi lại thay vì để người sau đoán:
///
/// 1. **Nhận mọi định dạng iOS đọc được** (quyết định đã chốt #6): không tự viết bộ đọc WAV mà để
///    `AVAudioFile` lo — nó đọc được `.m4a`, `.mp3`, `.wav`, `.caf`, `.aiff`, … cùng mọi tần số lấy mẫu.
/// 2. **`startAccessingSecurityScopedResource()` + copy sang thư mục tạm trước khi nhả khoá**: file người
///    dùng chọn từ iCloud/Files chỉ đọc được trong lúc khoá còn mở. Đọc thẳng rồi mới nhả là mở đường cho
///    lỗi quyền chỉ nổ trên máy có iCloud — mà `AVAudioFile` giữ đường dẫn chứ không giữ nội dung.
///
/// Đầu ra **luôn mono**. Upstream dùng `soxr` chất lượng HQ; ở đây dùng `AVAudioConverter` với chất lượng
/// `.max` + thuật toán `mastering`. **Không bit-identical với soxr** — đây là sai lệch đã biết, và đã đo
/// là chấp nhận được: §5.3 cho `style` std 0,11347 nằm gọn trong dải preset 0,10680–0,11979, x-vector
/// chỉ lệch ~1 % giữa hai cách lấy mẫu khác nhau.
enum VieNeuAudioResampler {
    /// Audio đã giải mã: mono float32 và tần số lấy mẫu **gốc của file**.
    struct Decoded {
        let samples: [Float]
        let sampleRate: Double

        var duration: Double {
            sampleRate > 0 ? Double(samples.count) / sampleRate : 0
        }
    }

    enum AudioError: LocalizedError {
        case unreadable(String)
        case empty
        case bufferAllocation
        case converterUnavailable
        case conversionFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let reason):
                return "Không đọc được file audio: \(reason)"
            case .empty:
                return "File audio không có mẫu nào."
            case .bufferAllocation:
                return "Không cấp được buffer để giải mã audio."
            case .converterUnavailable:
                return "Không dựng được bộ đổi tần số lấy mẫu."
            case .conversionFailed(let reason):
                return "Đổi tần số lấy mẫu thất bại: \(reason)"
            }
        }
    }

    /// Giải mã **toàn bộ** file thành mono float32 ở tần số gốc.
    static func loadMono(url: URL) throws -> Decoded {
        let secured = try securedCopyIfNeeded(url)
        defer { if secured.isTemporary { try? FileManager.default.removeItem(at: secured.url) } }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: secured.url)
        } catch {
            throw AudioError.unreadable(error.localizedDescription)
        }
        guard file.length > 0 else { throw AudioError.empty }
        // `processingFormat` của `AVAudioFile` luôn là float32 **không xen kẽ**, đúng thứ `floatChannelData`
        // cần — nên không phải tự dựng `AVAudioFormat` ở đây.
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw AudioError.bufferAllocation
        }
        do {
            try file.read(into: buffer)
        } catch {
            throw AudioError.unreadable(error.localizedDescription)
        }
        return Decoded(samples: mono(from: buffer), sampleRate: format.sampleRate)
    }

    /// Giải mã rồi lấy lại mẫu về `targetRate`. Trả về `[]` khi file rỗng.
    static func loadMono(url: URL, targetRate: Double) throws -> [Float] {
        let decoded = try loadMono(url: url)
        return try resample(decoded.samples, from: decoded.sampleRate, to: targetRate)
    }

    /// Lấy lại mẫu mono từ `sourceRate` sang `targetRate`. Tần số đã đúng thì trả nguyên mảng.
    static func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) throws -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard sourceRate > 0, targetRate > 0 else { throw AudioError.conversionFailed("tần số lấy mẫu không hợp lệ") }
        // Dưới 0,5 Hz coi như bằng nhau — tránh dựng converter chỉ để dịch vài phần nghìn Hz.
        guard abs(sourceRate - targetRate) > 0.5 else { return samples }

        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceRate,
            channels: 1,
            interleaved: false
        ), let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioError.converterUnavailable
        }
        guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = input.floatChannelData?[0] else {
            throw AudioError.bufferAllocation
        }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: samples.count) }
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioError.converterUnavailable
        }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm.mastering

        // Cấp dư 1024 frame: `convert(to:error:withInputFrom:)` **không** cho tiếp tục một lượt đã dừng
        // giữa đường (buffer vào chỉ được cấp một lần), nên output phải đủ chỗ cho trọn input trong một
        // lượt. Thiếu chỗ là mất đuôi audio **im lặng**.
        let ratio = targetRate / sourceRate
        let capacity = AVAudioFrameCount((Double(samples.count) * ratio).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity),
              let outputChannel = output.floatChannelData?[0] else {
            throw AudioError.bufferAllocation
        }

        var delivered = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if delivered {
                outStatus.pointee = .endOfStream
                return nil
            }
            delivered = true
            outStatus.pointee = .haveData
            return input
        }
        if status == .error {
            throw AudioError.conversionFailed(conversionError?.localizedDescription ?? "không rõ nguyên nhân")
        }
        return Array(UnsafeBufferPointer(start: outputChannel, count: Int(output.frameLength)))
    }

    // MARK: - Nội bộ

    /// Trung bình các kênh thành mono — đúng `wav.mean(axis=1)` của `_load_mono` trong upstream.
    private static func mono(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channels = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 1 else {
            return Array(UnsafeBufferPointer(start: channels[0], count: frames))
        }
        var result = [Float](repeating: 0, count: frames)
        for channel in 0..<channelCount {
            let data = channels[channel]
            for frame in 0..<frames { result[frame] += data[frame] }
        }
        let scale = 1 / Float(channelCount)
        for index in result.indices { result[index] *= scale }
        return result
    }

    /// File ngoài sandbox (iCloud/Files) phải được **copy** sang thư mục tạm trong lúc khoá
    /// security-scoped còn mở. File trong sandbox (bản thu của chính app, hoặc mẫu đã lưu ở
    /// `CustomVoices/samples/`) trả về nguyên đường dẫn, `isTemporary = false`.
    private static func securedCopyIfNeeded(_ url: URL) throws -> (url: URL, isTemporary: Bool) {
        guard url.startAccessingSecurityScopedResource() else {
            return (url, false)
        }
        defer { url.stopAccessingSecurityScopedResource() }

        var destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("vieneu-sample-\(UUID().uuidString)")
        let ext = url.pathExtension
        if !ext.isEmpty { destination = destination.appendingPathExtension(ext) }
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            throw AudioError.unreadable(error.localizedDescription)
        }
        return (destination, true)
    }
}
