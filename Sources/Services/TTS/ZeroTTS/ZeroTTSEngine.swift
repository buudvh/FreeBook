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

    /// `nil` khi không dựng được thư mục kho (Application Support không ghi được).
    static let shared: ZeroTTSEngine? = {
        guard let store = try? ZeroTTSModelStore() else { return nil }
        return ZeroTTSEngine(store: store)
    }()

    let store: ZeroTTSModelStore
    let threadCount: Int32

    private let lock = NSLock()
    private var runtime: ZeroTTSONNXRuntime?
    private var config: ZeroTTSConfig?
    private var tokenizer: ZeroTTSTokenizer?
    private var voices: [ZeroTTSVoiceCatalog.Voice] = []
    private var loadMs: Double = 0

    init(store: ZeroTTSModelStore, threadCount: Int32 = 4) {
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

    /// Nạp bốn graph + config + tokenizer. Idempotent: gọi lại khi đã nạp thì trả về ngay.
    ///
    /// Dựng **hết** vào biến cục bộ rồi mới gán — gán từng cái là mở đường cho trạng thái nửa vời, đúng
    /// lỗi đã gặp ở engine VieNeu (`VieNeuTTSEngine.swift:154-159`).
    func prepare() throws {
        lock.lock()
        defer { lock.unlock() }
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
            tokenizerReport: tokenizer.parityReport()
        )
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
    private func prepareLocked() throws {
        guard runtime == nil else { return }
        // `prepare()` tự khoá; ở đây đang giữ khoá nên phải làm lại phần thân thay vì gọi nó.
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
