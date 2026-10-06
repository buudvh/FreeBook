import Foundation
import OnnxRuntimeBindings

/// Bộ thi hành **Kokoro-Vietnamese** trên máy.
///
/// ## Không cần cầu C
/// Kokoro chỉ dùng tensor `int64` (`input_ids`) và `float32` (`ref_s`, `speed`) — đều nằm trong khả năng của
/// lớp ObjC `OnnxRuntimeBindings`, đúng lớp mà `ONNXPiperEngine` đang chạy (`:330-362`). Cầu C chỉ cần khi
/// phải tạo tensor **`bool`**, mà Kokoro không có tensor nào như vậy.
///
/// ## Một lượt cho cả câu
/// Khác ZeroTTS (2 lời gọi ORT cho **mỗi frame**), Kokoro chạy graph **một lần** cho cả chuỗi âm vị. Nên
/// không có "frame", không có KV cache, và `synthesisMs` chia làm hai phần rõ ràng: `g2pMs` (phiên âm) và
/// `sessionMs` (chạy graph).
///
/// ## Cấu hình ORT
/// Bắt chước `ONNXPiperEngine.swift:69-85`: **1 luồng** + thử **XNNPACK** rồi fallback CPU. Ghi chú ở đó nói
/// rõ lý do — chạy hai worker ORT liên tục làm tăng công suất gói trong lúc phát dài.
final class KokoroEngine: @unchecked Sendable {
    struct Output {
        let data: Data
        let samples: [Float]
        let sampleRate: Int
        let pcmDuration: Double
        let synthesisMs: Double
        /// Thời gian riêng phần **phiên âm** — để biết chi phí nằm ở G2P hay ở graph.
        let g2pMs: Double
        /// Thời gian riêng phần **chạy graph ONNX**.
        let sessionMs: Double
        let phonemeCount: Int
        let characterCount: Int
        /// Biên độ đỉnh của PCM. Gần `0` nghĩa là đọc sai output hoặc dtype — chặn ngay, đừng để người dùng
        /// nghe một file im lặng rồi tưởng model dở.
        let peakAmplitude: Float
        let loadMs: Double
        let g2pReport: String
    }

    enum EngineError: LocalizedError {
        case modelMissing([String])
        case noSeaG2P
        case notPrepared
        case emptyPhonemes
        case tooLong(Int)
        case silentOutput

        var errorDescription: String? {
            switch self {
            case .modelMissing(let names):
                return "Thiếu file model Kokoro: \(names.joined(separator: ", "))"
            case .noSeaG2P:
                return "Chưa có `sea_g2p.bin` — hãy tải model **VieNeu** trước, Kokoro dùng chung bộ phiên âm đó."
            case .notPrepared:
                return "Engine Kokoro chưa nạp xong. Bấm “Tải model” rồi thử lại."
            case .emptyPhonemes:
                return "Không sinh được âm vị nào từ văn bản này."
            case .tooLong(let count):
                return "Chuỗi âm vị \(count) vượt trần \(KokoroConfig.contextLength) của graph — hãy chia đoạn ngắn hơn."
            case .silentOutput:
                return "Graph trả về PCM im lặng — nghi đọc sai output hoặc sai kiểu dữ liệu."
            }
        }
    }

    /// Kho model. **`internal` chứ không `private`**: màn thử cần `engine.store` để lấy đường dẫn voicepack
    /// và để gọi `deleteAll()`. `private` trong Swift giới hạn theo **file**, nên một `private` ở đây là màn
    /// thử ở file khác không đọc được — đúng lỗi CI đã bắt ở lượt đầu.
    let store: KokoroModelStore
    private let lock = NSLock()

    /// `nil` khi không dựng được thư mục kho (Application Support không ghi được).
    ///
    /// Dùng chung một thực thể cho cả phiên: mỗi `KokoroEngine` giữ một `ORTSession` 310 MB, nên hai thực thể
    /// là hai bộ session trong RAM.
    static let shared: KokoroEngine? = {
        guard let store = try? KokoroModelStore() else { return nil }
        return KokoroEngine(store: store)
    }()

    private var env: ORTEnv?
    private var session: ORTSession?
    private var config: KokoroConfig?
    private var g2p: KokoroG2P?
    /// Tên output chứa waveform — **hỏi session** lúc nạp thay vì hardcode.
    private var waveformOutputName: String?
    private var loadMs: Double = 0

    init(store: KokoroModelStore) {
        self.store = store
    }

    var isPrepared: Bool {
        lock.lock(); defer { lock.unlock() }
        return session != nil
    }

    // MARK: - Nạp

    /// Nạp session ORT + config + G2P. Idempotent.
    func prepare() throws {
        lock.lock()
        defer { lock.unlock() }
        try prepareLocked()
    }

    private func prepareLocked() throws {
        guard session == nil else { return }
        let missing = store.missingNames
        guard missing.isEmpty else { throw EngineError.modelMissing(missing) }
        guard let seaG2PURL = store.seaG2PURL, store.hasSeaG2P else { throw EngineError.noSeaG2P }

        let started = ProcessInfo.processInfo.systemUptime
        let newEnv = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(1)
        try options.setGraphOptimizationLevel(.all)
        var provider = "cpu"
        do {
            let xnnpackOptions = ORTXnnpackExecutionProviderOptions()
            xnnpackOptions.intra_op_num_threads = 1
            try options.appendXnnpackExecutionProvider(with: xnnpackOptions)
            provider = "xnnpack"
        } catch {
            AppLogger.shared.log("ℹ️ [Kokoro] XNNPACK không khả dụng, dùng CPU provider: \(error.localizedDescription)")
        }
        let newSession = try ORTSession(env: newEnv,
                                        modelPath: store.url(for: KokoroModelStore.graphName).path,
                                        sessionOptions: options)
        let newConfig = try KokoroConfig.load(from: store.url(for: KokoroModelStore.configName))
        let newG2P = KokoroG2P(backend: try SeaG2P(binURL: seaG2PURL))

        // Hỏi tên output từ session thay vì hardcode — bản export khác có thể đặt tên khác.
        let outputNames = try newSession.outputNames()
        let waveformName = outputNames.first(where: { $0 == "waveform" }) ?? outputNames.first

        env = newEnv
        session = newSession
        config = newConfig
        g2p = newG2P
        waveformOutputName = waveformName
        loadMs = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        AppLogger.shared.log("🎙️ [Kokoro] Nạp xong: provider=\(provider), output=\(waveformName ?? "?"), \(Int(loadMs)) ms")
    }

    // MARK: - Tổng hợp

    func synthesize(text: String, voicepackURL: URL, speed: Double) throws -> Output {
        lock.lock()
        defer { lock.unlock() }
        try prepareLocked()
        return try synthesizeLocked(text: text, voicepackURL: voicepackURL, speed: speed)
    }

    private func synthesizeLocked(text: String, voicepackURL: URL, speed: Double) throws -> Output {
        guard let session, let config, let g2p, let waveformOutputName else { throw EngineError.notPrepared }

        let started = ProcessInfo.processInfo.systemUptime

        let g2pStarted = started
        let phonemes = g2p.phonemize(text)
        let g2pMs = (ProcessInfo.processInfo.systemUptime - g2pStarted) * 1_000
        guard !phonemes.isEmpty else { throw EngineError.emptyPhonemes }

        // `input_ids = [0, *ids, 0]` — 0 là BOS/EOS, đúng `phonemes_to_input_ids` của bản tham chiếu.
        let body = config.encode(phonemes: phonemes)
        guard body.count + 2 <= KokoroConfig.contextLength else { throw EngineError.tooLong(body.count + 2) }
        let ids = [Int64(0)] + body + [Int64(0)]

        let voicepack = try KokoroVoiceCatalog.loadVoicepack(from: voicepackURL)
        let style = try KokoroVoiceCatalog.styleVector(from: voicepack, phonemeCount: body.count)

        let inputIds = try makeTensor(ids, shape: [1, NSNumber(value: ids.count)])
        let refS = try makeTensor(style, shape: [1, NSNumber(value: style.count)])
        let speedValue = try makeTensor([Float(speed)], shape: [])

        let sessionStarted = ProcessInfo.processInfo.systemUptime
        let outputs = try session.run(
            withInputs: ["input_ids": inputIds, "ref_s": refS, "speed": speedValue],
            outputNames: Set([waveformOutputName]),
            runOptions: nil
        )
        let sessionMs = (ProcessInfo.processInfo.systemUptime - sessionStarted) * 1_000

        guard let waveform = outputs[waveformOutputName] else {
            throw EngineError.modelMissing(["output `\(waveformOutputName)`"])
        }
        let raw = try waveform.tensorData() as Data
        guard raw.count > MemoryLayout<Float>.size, raw.count % MemoryLayout<Float>.size == 0 else {
            throw EngineError.silentOutput
        }
        var samples = [Float](repeating: 0, count: raw.count / MemoryLayout<Float>.size)
        let byteCount = raw.count
        samples.withUnsafeMutableBytes { destination in
            raw.withUnsafeBytes { source in
                guard let base = source.baseAddress else { return }
                destination.copyBytes(from: UnsafeRawBufferPointer(start: base,
                                                                   count: min(destination.count, byteCount)))
            }
        }

        var peak: Float = 0
        for sample in samples { peak = max(peak, abs(sample)) }
        guard peak > 1e-5 else { throw EngineError.silentOutput }

        // Chuẩn hoá đỉnh như màn thử trên desktop, để so được với mẫu đã nghe.
        let gain = 0.95 / peak
        for index in samples.indices { samples[index] *= gain }

        let data = WAVEncoder.encodePCM16(samples: samples,
                                          sampleRate: KokoroConfig.sampleRate,
                                          channels: 1)
        return Output(
            data: data,
            samples: samples,
            sampleRate: KokoroConfig.sampleRate,
            pcmDuration: Double(samples.count) / Double(KokoroConfig.sampleRate),
            synthesisMs: (ProcessInfo.processInfo.systemUptime - started) * 1_000,
            g2pMs: g2pMs,
            sessionMs: sessionMs,
            phonemeCount: body.count,
            characterCount: text.count,
            peakAmplitude: peak,
            loadMs: loadMs,
            g2pReport: g2p.parityReport()
        )
    }

    /// `prepare()` ở `Task.detached` — nạp graph 310 MB là việc **nặng và đồng bộ**.
    func prepareAsync() async throws {
        try await Task.detached(priority: .utility) { [self] in
            try self.prepare()
        }.value
    }

    /// `synthesize(...)` ở `Task.detached`, cùng lý do như `prepareAsync`.
    func synthesizeAsync(text: String, voicepackURL: URL, speed: Double) async throws -> Output {
        try await Task.detached(priority: .userInitiated) { [self] in
            try self.synthesize(text: text, voicepackURL: voicepackURL, speed: speed)
        }.value
    }

    // MARK: - Tensor

    private func makeTensor(_ values: [Int64], shape: [NSNumber]) throws -> ORTValue {
        let data = values.withUnsafeBufferPointer { buffer -> Data in
            guard let base = buffer.baseAddress else { return Data() }
            return Data(bytes: base, count: buffer.count * MemoryLayout<Int64>.size)
        }
        return try ORTValue(tensorData: NSMutableData(data: data),
                            elementType: ORTTensorElementDataType.int64,
                            shape: shape)
    }

    private func makeTensor(_ values: [Float], shape: [NSNumber]) throws -> ORTValue {
        let data = values.withUnsafeBufferPointer { buffer -> Data in
            guard let base = buffer.baseAddress else { return Data() }
            return Data(bytes: base, count: buffer.count * MemoryLayout<Float>.size)
        }
        return try ORTValue(tensorData: NSMutableData(data: data),
                            elementType: ORTTensorElementDataType.float,
                            shape: shape)
    }
}
