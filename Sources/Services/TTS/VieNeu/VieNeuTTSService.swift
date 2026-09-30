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
final class VieNeuTTSService: LocalTTSEngine, @unchecked Sendable {
    /// Singleton **tạo lười**: `VieNeuModelStore()` có thể throw (không dựng được thư mục model) nên
    /// `nil` là trạng thái hợp lệ, và engine chỉ được dựng khi có người thật sự dùng — nạp 4 session ONNX
    /// + `sea_g2p.bin` 62,8 MB cho một engine chưa được chọn là việc không ai muốn.
    ///
    /// Dùng chung một thực thể là **bắt buộc**, không phải tiện: mỗi `VieNeuTTSEngine` giữ bốn
    /// `OrtSession` riêng, nên hai service là hai bộ session nằm trong RAM và hai đường suy luận tranh
    /// CPU — cùng lý do đã ghi ở `NghiTTSTextToolView` cho Piper.
    static let shared: VieNeuTTSService? = {
        guard let store = try? VieNeuModelStore() else { return nil }
        return VieNeuTTSService(store: store, engine: VieNeuTTSEngine(store: store))
    }()

    private let store: VieNeuModelStore
    private let engine: VieNeuTTSEngine
    private let syncQueue = DispatchQueue(label: "VieNeuTTSService.sync")
    private var _currentVoice: String?
    private var _lastDroppedScalars = 0
    private var _lastChunkCount = 0
    private var _lastPhonemeSample = ""
    private var _lastSpeechDuration = 0.0
    private var _lastVectorMs = 0.0
    private var _lastOtherMs = 0.0

    var currentVoice: String? {
        syncQueue.sync { _currentVoice }
    }

    var engineStatus: String {
        "VieNeu-TTS v3 Nano (ONNX, 24 kHz, CPU) — \(engine.currentMode.rawValue)"
    }

    /// Kho model, để màn thử giọng hiện được "đã tải / còn thiếu file nào / tốn bao nhiêu".
    var modelStore: VieNeuModelStore { store }

    /// Chế độ chất lượng đang chạy. Cùng với RTF đo được, đây là **dữ liệu quyết định** có nối engine
    /// vào Reader hay không — xem plan §7.
    var currentMode: VieNeuSynthesisPolicy.Mode { engine.currentMode }

    /// 4 session ONNX đã nạp xong chưa — màn thử giọng dùng để hiện "đang nạp engine…" ở lượt đầu.
    var isPrepared: Bool { engine.isPrepared }

    /// Số phoneme bị bỏ ở lượt tổng hợp gần nhất. Màn thử giọng đọc để phát hiện text không đọc được.
    var lastDroppedScalars: Int { syncQueue.sync { _lastDroppedScalars } }

    /// Số chunk của lượt tổng hợp gần nhất — xem doc của `VieNeuTTSEngine.Output.chunkCount`.
    var lastChunkCount: Int { syncQueue.sync { _lastChunkCount } }

    /// Phoneme của chunk đầu ở lượt gần nhất — bằng chứng để phân biệt "từ điển sai" với "model đọc
    /// phoneme tiếng Anh bằng giọng Việt".
    var lastPhonemeSample: String { syncQueue.sync { _lastPhonemeSample } }

    /// Độ dài audio trừ khoảng nghỉ đã chèn — mẫu số đúng để tính RTF thật.
    var lastSpeechDuration: Double { syncQueue.sync { _lastSpeechDuration } }

    /// Thời gian `vector_estimator` và phần còn lại của lượt gần nhất (ms) — để biết chậm ở đâu.
    var lastVectorMs: Double { syncQueue.sync { _lastVectorMs } }
    var lastOtherMs: Double { syncQueue.sync { _lastOtherMs } }

    /// Khoá `UserDefaults` của chế độ chất lượng.
    ///
    /// Đặt ở tầng service (không phải ở View) để màn thử giọng và đường đọc truyện — khi được nối —
    /// dùng **cùng một** giá trị, và để lựa chọn sống qua các lần mở app.
    private static let preferredModeKey = "vieneuPreferredMode"

    /// Chế độ người dùng chọn; `nil` = tự thích nghi theo tốc độ máy.
    var preferredMode: VieNeuSynthesisPolicy.Mode? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.preferredModeKey) else { return nil }
            return VieNeuSynthesisPolicy.Mode(rawValue: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: Self.preferredModeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.preferredModeKey)
            }
            engine.setRequestedMode(newValue)
        }
    }

    /// "Tiết kiệm pin" (opt-in): ép `fast` + 2 luồng ORT. Ép `fast` **ngay** (không chờ `prepare()`); tắt
    /// thì trả về lựa chọn người dùng (`preferredMode`) hoặc để tự thích nghi.
    var powerSaving: Bool {
        get { VieNeuSynthesisPolicy.isPowerSaving(.standard) }
        set {
            UserDefaults.standard.set(newValue, forKey: VieNeuSynthesisPolicy.powerSavingKey)
            if newValue {
                engine.setRequestedMode(.fast)
            } else {
                preferredMode = nil   // tắt Tiết kiệm pin ⇒ về "Tự động"
            }
        }
    }

    /// Số luồng ORT (2...4). Chỉ có hiệu lực khi **nạp lại engine** (session ORT dựng với số luồng này).
    var threadCount: Int {
        get { Int(VieNeuSynthesisPolicy.threadCount(from: .standard)) }
        set { UserDefaults.standard.set(max(2, min(4, newValue)), forKey: VieNeuSynthesisPolicy.threadCountKey) }
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
        // Áp lựa chọn đã lưu sau khi engine sẵn sàng — lần mở app sau vẫn giữ đúng chế độ người dùng đặt.
        // "Tiết kiệm pin" thắng: khi bật thì ép `fast` bất kể `preferredMode`.
        engine.setRequestedMode(powerSaving ? .fast : preferredMode)
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
        boundaryKind: TTSBoundaryKind = .paragraphEnd,
        priority: SynthesisPriority = .demand,
        requestID: UUID = UUID(),
        synthesisKey: String? = nil
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
        boundaryKind: TTSBoundaryKind = .paragraphEnd,
        priority: SynthesisPriority = .demand,
        requestID: UUID = UUID(),
        synthesisKey: String? = nil
    ) async throws -> (data: Data, pcmDuration: Double, queueWaitMs: Double, synthesisMs: Double) {
        let effectiveKey = synthesisKey ?? Self.makeDefaultSynthesisKey(
            text: text,
            voice: voice,
            speed: speed,
            boundaryKind: boundaryKind
        )
        let payload = try await PiperSynthesisCoordinator.shared.enqueuePayload(
            priority: priority,
            requestID: requestID,
            synthesisKey: effectiveKey
        ) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.executeInternalSynthesis(
                text: text,
                voice: voice,
                speed: speed,
                boundaryKind: boundaryKind
            )
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
        // KHÔNG có tham số `boundaryKind` ở đây: protocol `LocalTTSEngine` (`:43-51`) đã bỏ nó khỏi
        // `synthesizeStream`. Đường stream là "một chunk cho cả đoạn" nên `.paragraphEnd` đúng nghĩa.
        let effectiveKey = synthesisKey ?? Self.makeDefaultSynthesisKey(
            text: text,
            voice: voice,
            speed: speed,
            boundaryKind: .paragraphEnd
        )
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
                boundaryKind: .paragraphEnd,
                onChunkPayload: onChunkPayload
            )
        }
    }

    // MARK: - Nội bộ

    private func executeInternalSynthesis(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind
    ) async throws -> PiperSynthesisPayload {
        if PiperTTSService.isUnspeakable(text) {
            return silencePayload(text: text, speed: speed)
        }
        // Mở rộng số/ngày/tháng trước khi đưa cho engine — `sea_g2p.bin` không có chữ số, nếu không
        // `8/1999` bị nuốt 10 ký tự. Dùng entry chung `normalizeVietnameseText` (không espeak, vì vocab
        // VieNeu không chứa IPA), đồng nhất với NghiTTS xử lý số ở service qua `preprocess`.
        let normalizedText = TextPreprocessor.normalizeVietnameseText(text)
        let started = ProcessInfo.processInfo.systemUptime
        let output = try engine.synthesize(
            text: normalizedText,
            voiceName: voice,
            speed: speed,
            boundaryKind: boundaryKind
        )
        syncQueue.sync {
            _currentVoice = voice
            _lastDroppedScalars = output.droppedScalars
            _lastChunkCount = output.chunkCount
            _lastPhonemeSample = output.phonemeSample
            _lastSpeechDuration = output.speechDuration
            _lastVectorMs = output.timing.vectorMs
            _lastOtherMs = output.timing.otherMs
        }
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
        boundaryKind: TTSBoundaryKind,
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
        // Mở rộng số/ngày/tháng (xem chú thích ở `executeInternalSynthesis`) — áp dụng luôn cho đường
        // stream để thử giọng và nạp trước cũng đọc đúng số.
        let normalizedText = TextPreprocessor.normalizeVietnameseText(text)
        let output = try engine.synthesize(
            text: normalizedText,
            voiceName: voice,
            speed: speed,
            boundaryKind: boundaryKind
        )
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
    /// `boundaryKind` **phải** nằm trong khoá: nó quyết định khoảng lặng đuôi, nên hai lượt gọi cùng văn
    /// bản nhưng khác ranh giới là **hai audio khác nhau** — gộp chúng (coordinator coalesce theo khoá) sẽ
    /// trả sai khoảng lặng cho một trong hai. Piper cũng đưa `boundary=` vào khoá của nó.
    private static func makeDefaultSynthesisKey(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind
    ) -> String {
        let raw = "vieneu|\(voice)|\(speed)|\(boundaryKind.rawValue)|\(text)"
        var hash: UInt64 = 5381
        for byte in raw.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return "auto-\(String(hash, radix: 16))"
    }
}
