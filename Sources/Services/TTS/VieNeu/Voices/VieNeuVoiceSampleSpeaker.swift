import Foundation

/// Cho **một giọng VieNeu đọc đoạn mẫu** (~15 giây) để làm mẫu nhân bản sang model kia khi giọng không có mẫu gốc
/// (giọng có sẵn, giọng Turbo cũ không giữ `sample.wav`, giọng Nano mất file mẫu) — 1.3.937, `VieNeuVoiceCopyRunner`.
///
/// Đoạn văn cố định, đủ 6 thanh và hầu hết phụ âm đầu; tổng hợp **từng câu** bằng đúng engine của giọng (cùng đường với
/// thử giọng `VieNeuVoicePreviewPlayer`: `synthesizeWithDuration`, ưu tiên `.demand`) rồi nối thành một WAV 16-bit mono
/// trong thư mục tạm. Bên gọi xoá file khi xong. Bản nhân bản từ tiếng máy đọc có thể kém giống giọng gốc hơn — UI nói rõ.
enum VieNeuVoiceSampleSpeaker {
    enum SpeakError: LocalizedError {
        case engineUnavailable
        case empty

        var errorDescription: String? {
            switch self {
            case .engineUnavailable: return "Không dựng được engine VieNeu để đọc mẫu."
            case .empty: return "Giọng đọc mẫu không ra tiếng."
            }
        }
    }

    /// Đoạn mẫu (~64 âm tiết ≈ 15 giây).
    static let sentences = [
        "Sáng nay trời trong xanh, gió nhẹ thổi qua những rặng tre bên dòng sông quê.",
        "Bà cụ ngồi trước hiên nhà, kể chuyện ngày xưa cho đám trẻ nghe say sưa.",
        "Ai cũng mong được về thăm làng, uống chén trà nóng và ngắm cánh đồng lúa chín vàng.",
        "Gió chiều khẽ đưa hương bưởi, khiến lòng người thấy bình yên lạ thường."
    ]

    /// Đọc đoạn mẫu bằng giọng `selection`, trả URL file WAV tạm. Nặng (vài giây) — không chạy trên main.
    static func speak(_ selection: VieNeuVoiceSelection) async throws -> URL {
        let started = ProcessInfo.processInfo.systemUptime
        var samples: [Float] = []
        var sampleRate = 0.0
        for (index, sentence) in sentences.enumerated() {
            try Task.checkCancellation()
            let boundary: TTSBoundaryKind = index == sentences.count - 1 ? .paragraphEnd : .sentenceEnd
            let decoded = try decode(try await synthesize(sentence, selection: selection, boundary: boundary))
            if sampleRate == 0 { sampleRate = decoded.sampleRate }
            samples += try VieNeuAudioResampler.resample(decoded.samples, from: decoded.sampleRate, to: sampleRate)
        }
        guard sampleRate > 0, !samples.isEmpty else { throw SpeakError.empty }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vieneu-spoken-sample-\(UUID().uuidString).wav")
        try WAVEncoder.encodePCM16(samples: samples, sampleRate: Int(sampleRate.rounded()), channels: 1)
            .write(to: url, options: .atomic)
        AppLogger.shared.log(
            "🎙️ [VieNeuCopy] Giọng \(selection.key) đọc mẫu \(String(format: "%.1f", Double(samples.count) / sampleRate)) s " +
            "trong \(String(format: "%.0f", (ProcessInfo.processInfo.systemUptime - started) * 1_000)) ms"
        )
        return url
    }

    private static func synthesize(
        _ text: String,
        selection: VieNeuVoiceSelection,
        boundary: TTSBoundaryKind
    ) async throws -> Data {
        switch selection.model {
        case .nano:
            guard let service = VieNeuTTSService.shared else { throw SpeakError.engineUnavailable }
            if !service.isPrepared { try await service.prepare(voice: selection.voiceId) }
            return try await service.synthesizeWithDuration(
                text: text, voice: selection.voiceId, speed: 1.0, boundaryKind: boundary, priority: .demand
            ).data
        case .turbo:
            guard let service = VieNeuTurboTTSService.shared else { throw SpeakError.engineUnavailable }
            return try await service.synthesizeWithDuration(
                text: text, voice: selection.voiceId, speed: 1.0, boundaryKind: boundary, priority: .demand
            ).data
        }
    }

    /// WAV của engine ⇒ mono float qua đúng bộ đọc của nhân bản (`VieNeuAudioResampler`).
    private static func decode(_ data: Data) throws -> VieNeuAudioResampler.Decoded {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vieneu-spoken-part-\(UUID().uuidString).wav")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        return try VieNeuAudioResampler.loadMono(url: url)
    }
}
