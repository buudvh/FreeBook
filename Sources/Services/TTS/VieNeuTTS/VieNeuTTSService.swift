import Foundation

/// Engine on-device thứ hai của nhánh `nghitts`: VieNeu-TTS v3 Turbo.
///
/// Đối xứng `PiperTTSService` và đi qua **cùng** `PiperSynthesisCoordinator`. Điều đó là bắt buộc,
/// không phải tiện tay: bất biến "chỉ một tác vụ tổng hợp chạy tại một thời điểm" và bốn mức ưu tiên
/// của hàng chờ áp cho cả hai engine, vì cả hai đều tranh cùng số core.
///
/// Khác `PiperTTSService` ở ba điểm:
///
/// 1. Hồ sơ tiền xử lý là `.vieneu` — **không** phiên âm chữ Latin sang âm Việt, vì model đọc tiếng
///    Anh gốc. Xem `TTSPreprocessProfile`.
/// 2. Audio ra 48 kHz thay vì 22.05 kHz, nên WAV im lặng cũng phải 48 kHz để `AVAudioPlayer` không
///    nhảy sample rate giữa các chunk.
/// 3. Giọng là dữ liệu trong `voices_v3_turbo.json`, không phải file model riêng, nên 20 giọng dùng
///    chung một bộ model và `prepare(voice:)` không phụ thuộc tên giọng.
final class VieNeuTTSService: LocalTTSSynthesizing, @unchecked Sendable {
    /// Khoá UserDefaults lưu giọng VieNeu.
    ///
    /// Khai ở đây chứ không ở `TTSManager` vì `resolveVoiceName` đọc nó từ ngoài MainActor, còn
    /// `TTSManager` là `@MainActor` nên static của nó cũng bị cô lập theo.
    static let voiceKey = "vieneuVoice"

    private let store: VieNeuModelStore
    private let engine: ONNXVieNeuEngine
    private let syncQueue = DispatchQueue(label: "VieNeuTTSService.sync")
    private var _currentModel: String?

    var currentModel: String? {
        syncQueue.sync { _currentModel }
    }

    var engineStatus: String {
        store.isInstalled
            ? "VieNeu-TTS v3 Turbo (ONNX int8, 48 kHz) đang hoạt động."
            : "VieNeu-TTS v3 Turbo chưa tải model."
    }

    var voices: [VieNeuVoice] { engine.voices }
    var defaultVoiceName: String? { engine.defaultVoiceName }
    var isModelInstalled: Bool { store.isInstalled }

    init(store: VieNeuModelStore) {
        self.store = store
        self.engine = ONNXVieNeuEngine(store: store)
    }

    /// Nạp trước session, bảng embedding và từ điển.
    ///
    /// Không throw khi model chưa tải: đây là warm-up nền, chưa có model là trạng thái hợp lệ và
    /// người dùng sẽ thấy lỗi tường minh khi thật sự bấm phát.
    func prepare(voice: String) async throws {
        guard store.isInstalled else { return }
        let engine = self.engine
        try await Task.detached(priority: .utility) {
            try engine.prepare()
        }.value
        syncQueue.sync { _currentModel = voice }
    }

    func synthesize(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind,
        priority: SynthesisPriority,
        requestID: UUID,
        synthesisKey: String?
    ) async throws -> Data {
        try await synthesizeWithDuration(
            text: text,
            voice: voice,
            speed: speed,
            boundaryKind: boundaryKind,
            priority: priority,
            requestID: requestID,
            synthesisKey: synthesisKey
        ).data
    }

    func synthesizeWithDuration(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind,
        priority: SynthesisPriority,
        requestID: UUID,
        synthesisKey: String?
    ) async throws -> (data: Data, pcmDuration: Double, queueWaitMs: Double, synthesisMs: Double) {
        let payload = try await PiperSynthesisCoordinator.shared.enqueuePayload(
            priority: priority,
            requestID: requestID,
            synthesisKey: synthesisKey
        ) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.execute(text: text, voice: voice, boundaryKind: boundaryKind)
        }
        return (
            data: payload.data,
            pcmDuration: payload.pcmDuration,
            queueWaitMs: payload.queueWaitMs,
            synthesisMs: payload.synthesisMs
        )
    }

    // MARK: - Thực thi

    private func execute(
        text: String,
        voice: String,
        boundaryKind: TTSBoundaryKind
    ) async throws -> PiperSynthesisPayload {
        guard store.isInstalled else {
            let missing = store.missingFiles().map(\.rawValue).joined(separator: ", ")
            throw TTSError.modelNotCached("Bộ model VieNeu chưa tải xong (thiếu: \(missing)). Vào Cài đặt → Quản lý model để tải.")
        }

        syncQueue.sync { _currentModel = voice }

        if PiperTTSService.isUnspeakable(text) {
            return silencePayload(boundaryKind: boundaryKind)
        }

        let processed = await TextPreprocessor.shared.preprocess(text, profile: .vieneu)
        if PiperTTSService.isUnspeakable(processed) {
            return silencePayload(boundaryKind: boundaryKind)
        }

        let resolvedVoice = resolveVoiceName(voice)
        let engine = self.engine
        let result = try await Task.detached(priority: .userInitiated) {
            try engine.synthesize(text: processed, voiceName: resolvedVoice, boundaryKind: boundaryKind)
        }.value
        return PiperSynthesisPayload(data: result.data, pcmDuration: result.pcmDuration)
    }

    /// `TTSManager` truyền `selectedVoice` xuống — đó là giọng của **Piper**, vì hai engine dùng hai
    /// khoá lưu khác nhau (`nghittsVoice` và `vieneuVoice`) và hai bộ tên không giao nhau.
    ///
    /// Giải quyết ở đây thay vì sửa đường truyền của `TTSManager`: `selectedVoice` còn tham gia khoá
    /// tổng hợp và phép kiểm tra danh tính ở hai call site tổng hợp, nên đổi nó là chạm vào logic
    /// huỷ/hợp lệ của cả hàng chờ. Đổi giọng VieNeu vẫn xoá cache đúng nhờ setter `vieNeuVoiceName`.
    private func resolveVoiceName(_ requested: String) -> String {
        let names = Set(engine.voices.map(\.name))
        if names.contains(requested) { return requested }
        let stored = UserDefaults.standard.string(forKey: Self.voiceKey) ?? ""
        if names.contains(stored) { return stored }
        return engine.defaultVoiceName ?? requested
    }

    /// WAV im lặng ở **48 kHz**.
    ///
    /// Không dùng `PiperTTSService.buildSilenceStreamingPayload` vì hàm đó mặc định 22.05 kHz; trộn
    /// hai sample rate trong cùng một hàng chờ phát làm `AVAudioPlayer` phải cấu hình lại giữa các
    /// chunk và nghe thành tiếng tách.
    private func silencePayload(boundaryKind: TTSBoundaryKind) -> PiperSynthesisPayload {
        let sampleRate = 48_000
        let pause = max(0.05, ONNXVieNeuEngine.pauseDuration(for: boundaryKind))
        let count = max(1, Int(Double(sampleRate) * pause))
        let samples = [Float](repeating: 0, count: count)
        let wav = WAVEncoder.encodePCM16(samples: samples, sampleRate: sampleRate, channels: 1)
        return PiperSynthesisPayload(data: wav, pcmDuration: Double(count) / Double(sampleRate))
    }
}
