import Darwin
import Foundation

/// Bộ thi hành **ZeroTTS** trên máy — lớp duy nhất màn thử nói chuyện.
///
/// Trách nhiệm: nạp bốn graph một lần, giữ chúng qua các lượt, và biến `text` thành WAV. Vòng sinh frame
/// nằm ở `ZeroTTSGenerator`; tầng ONNX nằm ở `ZeroTTSONNXRuntime`; lớp này chỉ lo vòng đời và khoá.
///
/// **Khoá là bắt buộc, không phải cho đẹp.** Trạng thái `packed_kv`/`full_valid` nằm trong ngữ cảnh C và
/// bị ghi tại chỗ mỗi frame, nên hai lượt tổng hợp chồng nhau sẽ phá nhau theo cách không tất định. Cùng
/// lý do và cùng khuôn với `VieNeuTTSEngine` (`NSLock` bọc trọn lượt).
final class ZeroTTSEngine: @unchecked Sendable {
    /// Kết quả một lượt tổng hợp, kèm đủ số đo để quyết định go/no-go.
    struct Report {
        let data: Data
        let samples: [Float]
        let sampleRate: Int
        let pcmDuration: Double
        let synthesisMs: Double
        let frameCount: Int
        /// Thời gian nạp bốn graph ở lượt `prepare` gần nhất. Chỉ khác 0 ở lượt đầu.
        let loadMs: Double
        /// `phys_footprint` **sau** khi tổng hợp xong — đỉnh thật của tiến trình, không phải ước lượng.
        let residentBytes: Int64
        let characterCount: Int
        let textTokenCount: Int
        /// Kết quả đối chiếu tokenizer với mốc parity. Rỗng nghĩa là chưa chạy.
        let tokenizerReport: String
        /// Thời gian **làm nóng** — một lượt tổng hợp ngắn đẩy qua cả bốn graph ở `prepare`.
        ///
        /// ORT cấp phát arena và tối ưu ở lần `Run` **đầu tiên** của mỗi session, nên lượt tổng hợp thật đầu
        /// tiên luôn chậm hơn hẳn các lượt sau. Không làm nóng thì số RTF báo ra là của **lượt đầu**, không
        /// phải trạng thái ổn định — và đó là cách một spike tự lừa mình.
        let warmupMs: Double
        /// Biên độ đỉnh của PCM (thang `0…1`).
        ///
        /// Gần `0` nghĩa là audio **im lặng**. Đây là phép thử rẻ nhất để tách "không nghe thấy gì" thành hai
        /// nguyên nhân khác hẳn nhau: tầng **sinh** ra im lặng, hay tầng **phát** không kêu.
        let peakAmplitude: Float
        /// Chia nhỏ thời gian theo graph. Không có bảng này thì biết RTF mà không biết sửa ở đâu.
        let textEncoderMs: Double
        let coldStartMs: Double
        let localDecodeMs: Double
        let prefixStepMs: Double
        let codecMs: Double
        /// Trạng thái nhiệt lúc đo (`nominal`/`fair`/`serious`/`critical`).
        ///
        /// iOS hạ xung khi máy nóng, nên **một số RTF đo lúc `serious` là số của máy đã bị hãm**, không phải
        /// của máy nguội. Không ghi lại thì hai lượt đo cách nhau vài phút sẽ không so được với nhau — và
        /// nạp 903 MB rồi làm nóng là đủ để máy ấm lên.
        let thermalState: String
        let lowPowerMode: Bool
    }

    enum EngineError: LocalizedError {
        case modelIncomplete([String])
        case notPrepared
        case shapeMismatch(String)
        case noVoice(String)

        var errorDescription: String? {
            switch self {
            case .modelIncomplete(let names):
                return "Thiếu file model ZeroTTS: \(names.joined(separator: ", "))"
            case .notPrepared:
                return "Engine ZeroTTS chưa nạp xong. Bấm “Tải model” rồi thử lại."
            case .shapeMismatch(let detail):
                return "Graph và `config.json` không khớp: \(detail)"
            case .noVoice(let name):
                return "Không tìm thấy file giọng `\(name)`. Tải lại model để lấy đủ giọng preset."
            }
        }
    }

    /// Số luồng ORT mặc định khi chưa có lựa chọn nào được lưu.
    ///
    /// Trùng với trần của engine VieNeu (`VieNeuSynthesisPolicy.defaultThreadCount`) để hai engine local có
    /// cùng điểm xuất phát — nhưng **không** dùng chung khoá `UserDefaults`: hai engine dựng session riêng,
    /// nên lựa chọn tối ưu cho bộ graph này không suy ra được cho bộ graph kia.
    static let defaultThreadCount: Int32 = 4

    /// Khoá `UserDefaults` cho số luồng ORT của ZeroTTS.
    static let threadCountKey = "zerottsThreadCount"

    /// Miền cho phép. Dưới 2 thì mất song song; trên 8 thì iPhone không có đủ nhân vật lý.
    static let threadCountRange: ClosedRange<Int32> = 2...8

    /// Số luồng đã lưu, đã kẹp vào `threadCountRange`.
    static func storedThreadCount(_ defaults: UserDefaults = .standard) -> Int32 {
        let stored = defaults.object(forKey: threadCountKey) as? Int ?? Int(defaultThreadCount)
        return min(max(Int32(stored), threadCountRange.lowerBound), threadCountRange.upperBound)
    }

    /// `nil` khi không dựng được thư mục kho (Application Support không ghi được).
    static let shared: ZeroTTSEngine? = {
        guard let store = try? ZeroTTSModelStore() else { return nil }
        return ZeroTTSEngine(store: store, threadCount: storedThreadCount())
    }()

    let store: ZeroTTSModelStore

    /// Số luồng ORT của bốn session. **Đổi được** bằng `setThreadCount(_:)` — nhưng đổi là phải dựng lại
    /// session, xem doc của hàm đó.
    private(set) var threadCount: Int32

    private let lock = NSLock()
    private var runtime: ZeroTTSONNXRuntime?
    private var config: ZeroTTSConfig?
    private var tokenizer: ZeroTTSTokenizer?
    private var voices: [ZeroTTSVoiceCatalog.Voice] = []
    private var loadMs: Double = 0
    private var warmupMs: Double = 0

    init(store: ZeroTTSModelStore, threadCount: Int32 = ZeroTTSEngine.defaultThreadCount) {
        self.store = store
        self.threadCount = threadCount
    }

    var isPrepared: Bool {
        lock.lock(); defer { lock.unlock() }
        return runtime != nil
    }

    var isModelReady: Bool { store.isReady }

    var missingNames: [String] { store.missingNames }

    func availableVoices() throws -> [ZeroTTSVoiceCatalog.Voice] {
        lock.lock(); defer { lock.unlock() }
        if voices.isEmpty {
            voices = try ZeroTTSVoiceCatalog.load(from: store.url(for: "voices_index.json"))
        }
        return voices
    }

    /// Nạp bốn graph + config + tokenizer, rồi **làm nóng**. Idempotent: gọi lại khi đã nạp thì trả về ngay.
    func prepare() throws {
        lock.lock()
        defer { lock.unlock() }
        try prepareLocked()
    }

    /// Đổi số luồng ORT và **dựng lại cả bốn session**.
    ///
    /// Số luồng nằm trong `OrtSessionOptions` **lúc tạo session**, nên nó **không sửa được tại chỗ** — không
    /// có API nào đổi số luồng của một `OrtSession` đã tạo. Vì vậy quét số luồng là phép đo **thủ công**:
    /// mỗi mức tốn lại ~17 s nạp 903 MB + ~1 s làm nóng. Đó là lý do màn thử có nút "Áp dụng & dựng lại"
    /// chứ không tự quét ngầm.
    ///
    /// Nhả ngữ cảnh cũ **trước** khi dựng mới: giữ cả hai cùng lúc là ~1,8 GB, đủ để bị jetsam.
    func setThreadCount(_ value: Int32) throws {
        lock.lock()
        defer { lock.unlock() }
        let clamped = min(max(value, Self.threadCountRange.lowerBound), Self.threadCountRange.upperBound)
        guard clamped != threadCount || runtime == nil else { return }
        threadCount = clamped
        UserDefaults.standard.set(Int(clamped), forKey: Self.threadCountKey)
        runtime = nil
        warmupMs = 0
        try prepareLocked()
    }

    /// `setThreadCount(_:)` ở `Task.detached` — dựng lại bốn session là việc nặng và đồng bộ.
    func setThreadCountAsync(_ value: Int32) async throws {
        try await Task.detached(priority: .utility) { [self] in
            try self.setThreadCount(value)
        }.value
    }

    /// Đối chiếu shape **graph khai** với `config.json`. Hai nguồn này lệch nhau nghĩa là weights và config
    /// không cùng một bản — chặn ở đây rẻ hơn nhiều so với để nó nổ ở `prefix_step`.
    static func validate(shapes: ZeroTTSORTShapes, against config: ZeroTTSConfig) throws {
        var problems: [String] = []
        if shapes.codebooks > 0, Int(shapes.codebooks) != config.numCodebooks {
            problems.append("codebooks \(shapes.codebooks) ≠ \(config.numCodebooks)")
        }
        if shapes.codebookSize > 0, Int(shapes.codebookSize) != config.codebookSize {
            problems.append("codebookSize \(shapes.codebookSize) ≠ \(config.codebookSize)")
        }
        if shapes.layers > 0, Int(shapes.layers) != config.nLayers {
            problems.append("layers \(shapes.layers) ≠ \(config.nLayers)")
        }
        if shapes.heads > 0, Int(shapes.heads) != config.nHeads {
            problems.append("heads \(shapes.heads) ≠ \(config.nHeads)")
        }
        if shapes.headDim > 0, Int(shapes.headDim) != config.headDim {
            problems.append("headDim \(shapes.headDim) ≠ \(config.headDim)")
        }
        if shapes.dModel > 0, Int(shapes.dModel) != config.dModel {
            problems.append("dModel \(shapes.dModel) ≠ \(config.dModel)")
        }
        guard problems.isEmpty else { throw EngineError.shapeMismatch(problems.joined(separator: "; ")) }
    }

    /// `text` → WAV. `text` tới đây đã qua `TTSReplacementManager.applyReplacements` ở tầng gọi.
    ///
    /// ZeroTTS **không** có lớp phiên âm kiểu espeak: model tự đọc số, ngày và viết tắt. Vì vậy ở đây cố ý
    /// **không** gọi `TextPreprocessor.normalizeVietnameseText` — đó là lớp của engine local khác, và mở
    /// rộng số thành chữ trước khi vào model là làm lệch khỏi bản tham chiếu.
    func synthesize(text: String, voice: String,
                    sampling: ZeroTTSConfig.Sampling = ZeroTTSConfig.Sampling(),
                    seed: UInt64 = 0x5EED) throws -> Report {
        lock.lock()
        defer { lock.unlock() }
        try prepareLocked()
        return try synthesizeLocked(text: text, voice: voice, sampling: sampling, seed: seed)
    }

    /// Thân một lượt tổng hợp, khi **đã** giữ khoá và engine đã nạp xong.
    ///
    /// Tách khỏi `synthesize` vì `prepareLocked` cần gọi nó để **làm nóng** mà `NSLock` không tái nhập —
    /// gọi `synthesize` từ trong `prepareLocked` là tự khoá chết.
    private func synthesizeLocked(text: String, voice: String,
                                  sampling: ZeroTTSConfig.Sampling, seed: UInt64) throws -> Report {
        guard let runtime, let config, let tokenizer else { throw EngineError.notPrepared }

        let voiceURL = store.url(for: ZeroTTSModelStore.voiceFileName(voice))
        guard FileManager.default.fileExists(atPath: voiceURL.path) else { throw EngineError.noVoice(voice) }
        let embedding = try ZeroTTSVoiceCatalog.loadEmbedding(
            from: voiceURL, expectedCount: config.nVoiceQueries * config.dModel)

        let generator = ZeroTTSGenerator(runtime: runtime, config: config, tokenizer: tokenizer,
                                         voiceEmbedding: embedding, sampling: sampling, seed: seed)
        let output = try generator.synthesize(text: text)
        let data = WAVEncoder.encodePCM16(samples: output.samples,
                                          sampleRate: output.sampleRate,
                                          channels: 1)
        var peak: Float = 0
        for sample in output.samples { peak = max(peak, abs(sample)) }
        return Report(
            data: data,
            samples: output.samples,
            sampleRate: output.sampleRate,
            pcmDuration: Double(output.samples.count) / Double(max(1, output.sampleRate)),
            synthesisMs: output.synthesisMs,
            frameCount: output.frameCount,
            loadMs: loadMs,
            residentBytes: Self.residentBytes(),
            characterCount: text.count,
            textTokenCount: tokenizer.encode(text).count,
            tokenizerReport: tokenizer.parityReport(),
            warmupMs: warmupMs,
            peakAmplitude: peak,
            textEncoderMs: output.textEncoderMs,
            coldStartMs: output.coldStartMs,
            localDecodeMs: output.localDecodeMs,
            prefixStepMs: output.prefixStepMs,
            codecMs: output.codecMs,
            thermalState: Self.thermalStateName(),
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    /// Tên trạng thái nhiệt lúc đo. Xem doc của `Report.thermalState` để biết vì sao nó phải có mặt.
    static func thermalStateName() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    /// `prepare()` ở `Task.detached` — nạp bốn graph (~903 MB) là việc **nặng và đồng bộ**, gọi thẳng từ
    /// một `Task` của View là chặn main thread suốt vài giây. Cùng khuôn và cùng mức ưu tiên với
    /// `VieNeuTTSService.prepare`.
    func prepareAsync() async throws {
        try await Task.detached(priority: .utility) { [self] in
            try self.prepare()
        }.value
    }

    /// `synthesize(...)` ở `Task.detached`, cùng lý do như `prepareAsync`.
    ///
    /// **Huỷ không xuyên qua được `Task.detached`** (nó không thừa hưởng cancellation của cha). Nút "Dừng"
    /// của màn thử vì vậy ngắt **phát** và bỏ kết quả, chứ không cắt ngang vòng sinh frame — màn thử ghi rõ
    /// điều đó ở footer. Muốn cắt thật thì phải luồn một cờ huỷ vào `ZeroTTSGenerator`, việc của lượt sau.
    func synthesizeAsync(text: String, voice: String,
                         sampling: ZeroTTSConfig.Sampling = ZeroTTSConfig.Sampling(),
                         seed: UInt64 = 0x5EED) async throws -> Report {
        try await Task.detached(priority: .userInitiated) { [self] in
            try self.synthesize(text: text, voice: voice, sampling: sampling, seed: seed)
        }.value
    }

    /// `prepare()` khi đã giữ khoá. Tách ra vì `synthesize` cần nạp mà **không** được khoá lại (NSLock
    /// không tái nhập).
    ///
    /// Dựng **hết** vào biến cục bộ rồi mới gán — gán từng cái là mở đường cho trạng thái nửa vời, đúng
    /// lỗi đã gặp ở engine VieNeu (`VieNeuTTSEngine.swift:154-159`).
    private func prepareLocked() throws {
        guard runtime == nil else { return }

        let missing = store.missingNames
        guard missing.isEmpty else { throw EngineError.modelIncomplete(missing) }

        let started = ProcessInfo.processInfo.systemUptime
        let newRuntime = try ZeroTTSONNXRuntime(modelDirectory: store.rootURL, threadCount: threadCount)
        let newConfig = try ZeroTTSConfig.load(from: store.url(for: "config.json"))
        let newTokenizer = try ZeroTTSTokenizer(tokenizerJSONURL: store.url(for: "tokenizer.json"))
        let newVoices = try ZeroTTSVoiceCatalog.load(from: store.url(for: "voices_index.json"))
        try Self.validate(shapes: newRuntime.shapes, against: newConfig)

        runtime = newRuntime
        config = newConfig
        tokenizer = newTokenizer
        voices = newVoices
        loadMs = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        AppLogger.shared.log("🎙️ [ZeroTTS] Nạp xong: \(newVoices.count) giọng, nạp \(Int(loadMs)) ms")

        // **Làm nóng** ngay sau khi nạp — xem doc của `Report.warmupMs`. Không có bước này thì lượt tổng hợp
        // thật đầu tiên gánh toàn bộ chi phí khởi tạo lười của ORT (cấp arena + tối ưu graph ở lần `Run` đầu
        // của mỗi session), và số RTF báo ra là của lượt đầu chứ không phải trạng thái ổn định. Bản port JS
        // cũng có `warmup()` đúng vì lý do này (`js/src/synthesizer.ts`).
        //
        // `try?` là cố ý: làm nóng **không** được phép làm hỏng việc nạp. Hỏng thì `warmupMs` giữ 0 và số đo
        // vẫn trung thực (nó chỉ là số của lượt đầu).
        if let voice = newVoices.first?.name {
            let warmupStarted = ProcessInfo.processInfo.systemUptime
            _ = try? synthesizeLocked(text: "a", voice: voice,
                                      sampling: ZeroTTSConfig.Sampling(), seed: 0x5EED)
            warmupMs = (ProcessInfo.processInfo.systemUptime - warmupStarted) * 1_000
            AppLogger.shared.log("🎙️ [ZeroTTS] Làm nóng xong: \(Int(warmupMs)) ms")
        }
    }

    /// `phys_footprint` của tiến trình — đỉnh bộ nhớ **thật** mà iOS dùng để quyết định jetsam.
    ///
    /// Cố ý không dùng `os_proc_available_memory()`: hàm đó trả phần **còn lại**, mà thứ cần báo cáo là
    /// phần đã dùng. Trả `0` khi `task_info` thất bại (không có số còn hơn có số sai).
    static func residentBytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int64(info.phys_footprint)
    }
}
