import Foundation
#if canImport(AudioCpp)
import AudioCpp
#endif

/// Bọc C API của **audio.cpp** (`include/audiocpp.h`, tag `v0.9.4`, ABI 0.2) để chạy VieNeu-TTS v3 Turbo GGUF.
///
/// ## Một hàng đợi tuần tự giữ mọi handle
/// Header nói rõ: handle **không** an toàn đa luồng, và `audiocpp_last_error()` là **thread-local** — phải đọc ngay sau
/// lời gọi hỏng, trên cùng luồng, trước mọi lời gọi audio.cpp khác (kể cả `*_free`). Vì vậy registry / model / session
/// chỉ được chạm trong `queue` (serial), và mỗi việc là **một** block nên lời gọi hỏng + đọc lỗi luôn chung một luồng.
/// Không dùng `actor`: `audiocpp_session_run` chặn nhiều giây, đặt lên pool hợp tác của Swift là giữ chết một luồng của
/// pool. Giải phóng cũng chạy trên `queue` ⇒ tự chờ lượt tổng hợp đang chạy xong.
///
/// ## Nạp một lần
/// Model (GGUF 188 MB) nạp một lần và giữ tới `release()`. Đổi số luồng chỉ dựng lại **session**
/// (`audiocpp_backend_config.threads` gắn với session), không nạp lại model.
///
/// ## Bản build không có framework
/// Mọi chỗ chạm `AudioCpp` nằm trong `#if canImport(AudioCpp)`; nhánh còn lại ném `RuntimeError.unavailable` để app vẫn
/// biên dịch được khi CI chưa dựng `AudioCpp.xcframework`.
final class VieNeuTurboRuntime: @unchecked Sendable {
    enum RuntimeError: LocalizedError {
        case unavailable
        case notLoaded
        case call(String, String)
        case noAudio

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Bản build này chưa có audio.cpp (thiếu AudioCpp.xcframework)."
            case .notLoaded: return "Chưa nạp model Turbo."
            case .call(let function, let detail): return "\(function) lỗi: \(detail)"
            case .noAudio: return "audio.cpp không trả âm thanh nào."
            }
        }
    }

    struct LoadReport: Sendable {
        /// `nil` khi model đã nạp từ trước (lượt này không nạp lại).
        let modelLoadMs: Double?
        /// `nil` khi session cũ dùng lại được (cùng số luồng).
        let sessionCreateMs: Double?
        let threads: Int
    }

    struct Output: Sendable {
        /// Âm thanh **mono** (đã trộn trung bình các kênh), float −1…1.
        let samples: [Float]
        let sampleRate: Int
        /// Số kênh audio.cpp trả về (model ra stereo ⇒ 2), để ghi log.
        let sourceChannels: Int
        /// Thời gian tường của riêng `audiocpp_session_run`.
        let runMs: Double
        /// CPU-time **cả tiến trình** trong lúc `audiocpp_session_run` chạy (`ProcessCPUClock`).
        let cpuMs: Double

        var durationSeconds: Double { Double(samples.count) / Double(max(1, sampleRate)) }
    }

    static let family = "vieneu_v3_turbo"

    /// QoS của hàng đợi — và của luồng ggml (luồng CPU của ggml dựng từ luồng gọi). Để `.utility` cho **cùng mức** với
    /// Nano: session ORT của Nano dựng ở `Task.detached(priority: .utility)`, và màn thử chạy lượt Nano ở `.utility`
    /// (`VieNeuTurboSoakRunner`). Trên iPhone, QoS ảnh hưởng chuyện chạy lõi hiệu năng hay lõi tiết kiệm — đúng biến số
    /// đang đo — nên hai engine phải chung một mức.
    static let qos: DispatchQoS = .utility
    static let qosName = "utility"

    private let queue = DispatchQueue(label: "VieNeuTurboRuntime", qos: VieNeuTurboRuntime.qos)
    // Chỉ đọc / ghi trong `queue`.
    private var registry: OpaquePointer?
    private var model: OpaquePointer?
    private var session: OpaquePointer?
    private var sessionThreads = 0
    private var loadedModelPath: String?

    static var isAvailable: Bool {
        #if canImport(AudioCpp)
        return true
        #else
        return false
        #endif
    }

    /// "audio.cpp 0.9.4 · ABI 0.2.0" — để màn thử và log ghi đúng bản thư viện đang chạy.
    static var versionDescription: String {
        #if canImport(AudioCpp)
        let abi = audiocpp_abi_version()
        let build = String(cString: audiocpp_build_version())
        return "audio.cpp \(build) · ABI \(abi >> 16).\((abi >> 8) & 0xff).\(abi & 0xff)"
        #else
        return "chưa có audio.cpp trong bản build"
        #endif
    }

    deinit {
        // Không còn ai giữ `self` ⇒ không còn block nào trên `queue` (block nào cũng giữ mạnh `self`).
        freeAll()
    }

    // MARK: - API

    /// Nạp model (nếu chưa) và dựng session CPU với `threads` luồng (nếu chưa có hoặc khác số luồng).
    func prepare(modelURL: URL, threads: Int) async throws -> LoadReport {
        try await perform { [self] in try prepareLocked(modelPath: modelURL.path, threads: max(1, threads)) }
    }

    /// Tổng hợp **một** chuỗi phiên âm sea-g2p với một giọng đóng gói (mã tham chiếu + speaker embedding).
    /// Không huỷ được giữa chừng — audio.cpp không có cổng huỷ; người gọi tự bỏ kết quả nếu đã dừng.
    func synthesize(phonemes: String, referenceCodesURL: URL, speakerEmbeddingURL: URL) async throws -> Output {
        try await perform { [self] in
            try synthesizeLocked(
                phonemes: phonemes,
                referenceCodesPath: referenceCodesURL.path,
                speakerEmbeddingPath: speakerEmbeddingURL.path
            )
        }
    }

    /// Nhả session → model → registry. Chạy sau lượt tổng hợp đang dở (cùng `queue`).
    func release() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                freeAll()
                continuation.resume()
            }
        }
    }

    // MARK: - Nội bộ

    private func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    private func freeAll() {
        #if canImport(AudioCpp)
        audiocpp_session_free(session)
        audiocpp_model_free(model)
        audiocpp_registry_free(registry)
        #endif
        session = nil
        model = nil
        registry = nil
        sessionThreads = 0
        loadedModelPath = nil
    }

    private static func elapsedMs(since start: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1_000
    }

    #if canImport(AudioCpp)
    /// Status khác `AUDIOCPP_OK` ⇒ đọc `audiocpp_last_error()` **ngay** (thread-local, lời gọi sau có thể xoá nó).
    private static func check(_ status: audiocpp_status, _ function: String) throws {
        guard status != AUDIOCPP_OK else { return }
        let detail = String(cString: audiocpp_last_error())
        let name = String(cString: audiocpp_status_string(status))
        throw RuntimeError.call(function, "\(name) — \(detail)")
    }

    private func prepareLocked(modelPath: String, threads: Int) throws -> LoadReport {
        if registry == nil {
            var created: OpaquePointer?
            try Self.check(audiocpp_registry_create(nil, &created), "audiocpp_registry_create")
            registry = created
        }

        var modelLoadMs: Double?
        if model == nil || loadedModelPath != modelPath {
            audiocpp_session_free(session)
            session = nil
            sessionThreads = 0
            audiocpp_model_free(model)
            model = nil
            loadedModelPath = nil

            let started = ProcessInfo.processInfo.systemUptime
            var loaded: OpaquePointer?
            // `family_hint` là `const char *` trong struct ⇒ dựng struct và gọi **bên trong** `withCString`.
            let status: audiocpp_status = Self.family.withCString { family in
                var config = audiocpp_model_config(
                    family_hint: family,
                    config_id: nil,
                    weight_id: nil,
                    model_spec_override: nil
                )
                return audiocpp_model_load(registry, modelPath, &config, nil, &loaded)
            }
            try Self.check(status, "audiocpp_model_load")
            model = loaded
            loadedModelPath = modelPath
            modelLoadMs = Self.elapsedMs(since: started)
            let family = audiocpp_model_family(loaded).map { String(cString: $0) } ?? "?"
            let supportsTTS = audiocpp_model_supports(loaded, "tts", "offline") == 1
            AppLogger.shared.log(
                "🎙️ [VieNeuTurbo] Nạp model \(String(format: "%.0f", modelLoadMs ?? 0)) ms — family=\(family), tts offline=\(supportsTTS ? "có" : "KHÔNG"), \(Self.versionDescription)"
            )
        }

        var sessionCreateMs: Double?
        if session == nil || sessionThreads != threads {
            audiocpp_session_free(session)
            session = nil
            let started = ProcessInfo.processInfo.systemUptime
            var created: OpaquePointer?
            let status: audiocpp_status = "cpu".withCString { backendName in
                var backend = audiocpp_backend_config(backend: backendName, device: 0, threads: Int32(threads))
                return audiocpp_session_create(model, "tts", "offline", &backend, nil, &created)
            }
            try Self.check(status, "audiocpp_session_create")
            session = created
            sessionThreads = threads
            sessionCreateMs = Self.elapsedMs(since: started)
            AppLogger.shared.log(
                "🎙️ [VieNeuTurbo] Dựng session CPU \(threads) luồng: \(String(format: "%.0f", sessionCreateMs ?? 0)) ms"
            )
        }
        return LoadReport(modelLoadMs: modelLoadMs, sessionCreateMs: sessionCreateMs, threads: threads)
    }

    private func synthesizeLocked(
        phonemes: String,
        referenceCodesPath: String,
        speakerEmbeddingPath: String
    ) throws -> Output {
        guard let session else { throw RuntimeError.notLoaded }
        guard let request = audiocpp_request_create() else {
            throw RuntimeError.call("audiocpp_request_create", "không cấp phát được request")
        }
        defer { audiocpp_request_free(request) }

        // `language` = nil: chuỗi rỗng / khác nil còn ghi `options["language"]`, mà family này từ chối option lạ.
        try Self.check(audiocpp_request_set_text(request, phonemes, nil), "audiocpp_request_set_text")
        try Self.check(
            audiocpp_request_set_option(request, "reference_codes_file", referenceCodesPath),
            "audiocpp_request_set_option(reference_codes_file)"
        )
        try Self.check(
            audiocpp_request_set_option(request, "speaker_embedding_file", speakerEmbeddingPath),
            "audiocpp_request_set_option(speaker_embedding_file)"
        )

        var result: OpaquePointer?
        let started = ProcessInfo.processInfo.systemUptime
        let cpuStarted = ProcessCPUClock.nowMs()
        let status = audiocpp_session_run(session, request, &result)
        let runMs = Self.elapsedMs(since: started)
        let cpuMs = ProcessCPUClock.nowMs() - cpuStarted
        try Self.check(status, "audiocpp_session_run")
        guard let result else { throw RuntimeError.noAudio }
        defer { audiocpp_result_free(result) }

        var samplesPointer: UnsafePointer<Float>?
        var frames = 0
        var sampleRate: Int32 = 0
        var channels: Int32 = 0
        try Self.check(
            audiocpp_result_audio(result, &samplesPointer, &frames, &sampleRate, &channels),
            "audiocpp_result_audio"
        )
        guard let samplesPointer, frames > 0, channels > 0, sampleRate > 0 else { throw RuntimeError.noAudio }

        // Con trỏ **mượn**: chép ra (đồng thời trộn về mono) trước khi `audiocpp_result_free` chạy ở `defer`.
        let interleaved = UnsafeBufferPointer(start: samplesPointer, count: frames * Int(channels))
        return Output(
            samples: Self.downmixToMono(interleaved, channels: Int(channels)),
            sampleRate: Int(sampleRate),
            sourceChannels: Int(channels),
            runMs: runMs,
            cpuMs: cpuMs
        )
    }
    #else
    private func prepareLocked(modelPath: String, threads: Int) throws -> LoadReport {
        throw RuntimeError.unavailable
    }

    private func synthesizeLocked(
        phonemes: String,
        referenceCodesPath: String,
        speakerEmbeddingPath: String
    ) throws -> Output {
        throw RuntimeError.unavailable
    }
    #endif

    /// Float **interleaved** ⇒ mono bằng trung bình các kênh (model ra stereo 48 kHz).
    static func downmixToMono(_ interleaved: UnsafeBufferPointer<Float>, channels: Int) -> [Float] {
        guard channels > 1 else { return Array(interleaved) }
        let frameCount = interleaved.count / channels
        let scale = 1 / Float(channels)
        var mono = [Float](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            let base = frame * channels
            var sum: Float = 0
            for channel in 0..<channels {
                sum += interleaved[base + channel]
            }
            mono[frame] = sum * scale
        }
        return mono
    }
}
