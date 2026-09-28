import Foundation

/// Facade của engine **VieNeu-TTS v3 Nano**, song song `PiperTTSService`.
///
/// Bốn điểm **cố ý giống hệt** `PiperTTSService` để tầng trên (`TTSManager`, `TTSChapterPrefetcher`,
/// `TTSNextChapterPrefixCache`, `TTSNextChapterPrefixSynthesizer`) nối vào bằng cùng một khuôn:
///
/// 1. Cùng đi qua `PiperSynthesisCoordinator` ⇒ thừa hưởng nguyên 4 mức ưu tiên, coalescing và
///    `promote(synthesisKey:)`. Không dựng hàng đợi thứ hai.
/// 2. Cùng nhận `synthesisKey` từ `TTSSynthesisIdentity` ở tầng trên; facade tự sinh key mặc định khi
///    caller bỏ trống, cùng khuôn `auto-<digest>`.
/// 3. Cùng trả `(data, pcmDuration, queueWaitMs, synthesisMs)` để `TTSManager+NghiEnergy` đo được RTF.
/// 4. Cùng tái dùng `PiperTTSService.isUnspeakable` + `makeSilenceSpec` cho đoạn rỗng — **khác một
///    tham số**: `sampleRate: 24_000` thay vì mặc định 22.050 của Piper. Quên chỗ này thì mọi khoảng
///    nghỉ ngắn hơn ~8 % và lệch dần suốt chương.
///
/// **Hạn chế đã biết:** `synthesizeStream` phát **một** chunk cho cả đoạn văn, không phải từng câu.
/// Model Nano không có streaming cấp frame (chính model card ghi vậy) và engine hiện tổng hợp trọn
/// đoạn trong một lượt. Đường stream vì thế vẫn đúng chức năng nhưng mất lợi ích "nghe được trước khi
/// tổng hợp xong" — muốn có thì phải đẩy vòng lặp chunk trong `VieNeuTTSEngine.synthesize` ra thành
/// callback, là việc của lượt sau.
final class VieNeuTTSService: @unchecked Sendable {
    private let store: VieNeuModelStore
    private let engine: VieNeuTTSEngine
    private let syncQueue = DispatchQueue(label: "VieNeuTTSService.sync")
    private var _currentVoice: String?

    var currentVoice: String? {
        syncQueue.sync { _currentVoice }
    }

    var engineStatus: String {
        "VieNeu-TTS v3 Nano (ONNX, 24 kHz, CPU) — \(engine.currentMode.rawValue)"
    }

    init(store: VieNeuModelStore, engine: VieNeuTTSEngine) {
        self.store = store
        self.engine = engine
    }

    // MARK: - Chuẩn bị

    /// Nạp 4 session ONNX + `sea_g2p.bin` (62,8 MB). Chạy ở `Task.detached` vì đây là việc nặng và
    /// đồng bộ — cùng lý do và cùng mức ưu tiên với `PiperTTSService.prepare` (`:35`).
    func prepare(voice: String) async throws {
        try await Task.detached(priority: .utility) { [engine] in
            try engine.prepare()
        }.value
        syncQueue.sync { _currentVoice = voice }
    }

    /// 11 giọng preset. Cần `voices_v3_nano.json` đã tải; chưa tải thì ném lỗi để màn cấu hình hiện
    /// "chưa có model" thay vì danh sách rỗng khó hiểu.
    func availableVoices() throws -> [Voice] {
        try VieNeuVoiceCatalog.load(modelStore: store).presets.map(\.voice)
    }

    var defaultVoiceName: String? {
        try? VieNeuVoiceCatalog.load(modelStore: store).defaultVoiceName
    }

    // MARK: - Tổng hợp

    func synthesize(
        text: String,
        voice: String,
        speed: Double,
        priority: SynthesisPriority = .demand,
        requestID: UUID = UUID(),
        synthesisKey: String? = nil
    ) async throws -> Data {
        try await synthesizeWithDuration(
            text: text,
            voice: voice,
            speed: speed,
            priority: priority,
            requestID: requestID,
            synthesisKey: synthesisKey
        ).data
    }

    func synthesizeWithDuration(
        text: String,
        voice: String,
        speed: Double,
        priority: SynthesisPriority = .demand,
        requestID: UUID = UUID(),
        synthesisKey: String? = nil
    ) async throws -> (data: Data, pcmDuration: Double, queueWaitMs: Double, synthesisMs: Double) {
        let effectiveKey = synthesisKey ?? Self.makeDefaultSynthesisKey(text: text, voice: voice, speed: speed)
        let payload = try await PiperSynthesisCoordinator.shared.enqueuePayload(
            priority: priority,
            requestID: requestID,
            synthesisKey: effectiveKey
        ) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.executeInternalSynthesis(text: text, voice: voice, speed: speed)
        }
        return (
            data: payload.data,
            pcmDuration: payload.pcmDuration,
            queueWaitMs: payload.queueWaitMs,
            synthesisMs: payload.synthesisMs
        )
    }

    /// Một chunk cho cả đoạn — xem "Hạn chế đã biết" ở doc của type. `allowsCoalescing: false` đúng
    /// như `PiperTTSService.synthesizeStream` (`:125`): closure `onChunkPayload` chỉ thuộc waiter đầu
    /// tiên, gộp waiter thứ hai vào là mất sạch chunk PCM.
    func synthesizeStream(
        text: String,
        voice: String,
        speed: Double,
        priority: SynthesisPriority = .demand,
        requestID: UUID = UUID(),
        synthesisKey: String? = nil,
        onChunkPayload: @escaping @Sendable (TTSPCMChunkPayload) async throws -> Void
    ) async throws -> Data {
        let effectiveKey = synthesisKey ?? Self.makeDefaultSynthesisKey(text: text, voice: voice, speed: speed)
        return try await PiperSynthesisCoordinator.shared.enqueue(
            priority: priority,
            requestID: requestID,
            synthesisKey: effectiveKey,
            allowsCoalescing: false
        ) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.executeInternalSynthesisStream(
                text: text,
                voice: voice,
                speed: speed,
                onChunkPayload: onChunkPayload
            )
        }
    }

    // MARK: - Nội bộ

    private func executeInternalSynthesis(
        text: String,
        voice: String,
        speed: Double
    ) async throws -> PiperSynthesisPayload {
        if PiperTTSService.isUnspeakable(text) {
            return silencePayload(text: text, speed: speed)
        }
        let started = ProcessInfo.processInfo.systemUptime
        let output = try engine.synthesize(text: text, voiceName: voice, speed: speed)
        syncQueue.sync { _currentVoice = voice }
        // `synthesisMs` của engine đo bên trong (chỉ gồm ONNX), còn ở đây đo trọn lượt gọi — lấy số của
        // engine để RTF phản ánh đúng chi phí suy luận chứ không lẫn thời gian chờ khoá.
        _ = started
        return PiperSynthesisPayload(
            data: output.data,
            pcmDuration: output.pcmDuration,
            synthesisMs: output.synthesisMs
        )
    }

    private func executeInternalSynthesisStream(
        text: String,
        voice: String,
        speed: Double,
        onChunkPayload: @escaping @Sendable (TTSPCMChunkPayload) async throws -> Void
    ) async throws -> Data {
        if PiperTTSService.isUnspeakable(text) {
            let silence = PiperTTSService.buildSilenceStreamingPayload(
                text: text,
                speed: speed,
                sampleRate: engine.sampleRate
            )
            try await onChunkPayload(silence.chunkPayload)
            return silence.wavData
        }
        let output = try engine.synthesize(text: text, voiceName: voice, speed: speed)
        syncQueue.sync { _currentVoice = voice }
        try await onChunkPayload(TTSPCMChunkPayload(
            samples: output.samples,
            sampleRate: engine.sampleRate,
            chunkIndex: 0,
            totalChunks: 1,
            isLast: true
        ))
        return output.data
    }

    private func silencePayload(text: String, speed: Double) -> PiperSynthesisPayload {
        let spec = PiperTTSService.makeSilenceSpec(text: text, speed: speed, sampleRate: engine.sampleRate)
        let data = WAVEncoder.encodePCM16(samples: spec.samples, sampleRate: spec.sampleRate, channels: 1)
        return PiperSynthesisPayload(data: data, pcmDuration: spec.pcmDuration)
    }

    /// Key mặc định khi caller bỏ trống — cùng khuôn `auto-<digest>` của `PiperTTSService`, nhưng gồm cả
    /// **tên giọng** (Piper suy giọng từ file model, còn ở đây 11 giọng dùng chung một bộ graph nên
    /// thiếu tên giọng là hai giọng khác nhau gộp chung một kết quả).
    private static func makeDefaultSynthesisKey(text: String, voice: String, speed: Double) -> String {
        let raw = "vieneu|\(voice)|\(speed)|\(text)"
        var hash: UInt64 = 5381
        for byte in raw.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return "auto-\(String(hash, radix: 16))"
    }
}
