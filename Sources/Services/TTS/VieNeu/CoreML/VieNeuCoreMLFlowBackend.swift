import Foundation

/// Vòng Euler + codec của Nano qua **Core ML CPU-only (fp32)** — `VieNeuFlowBackend` của "Tăng tốc Core ML" (P2c): trình
/// đọc giữ nó ở `VieNeuCoreMLReaderRoute` (`isReader == true`: lỗi một chunk ⇒ engine chạy lại bằng ORT; chạy nháp + log
/// lượt đầu mỗi session ở `+Reader`); bước chuẩn bị (`VieNeuCoreMLAccelerator.compileAndVerify`) dựng một bản để biên
/// dịch + tự kiểm rồi gắn cho trình đọc.
///
/// - Graph tĩnh nhiều bucket (`VieNeuCoreMLPackage`): mỗi chunk chọn bucket nhỏ nhất ≥ T **riêng** cho VE và codec,
///   đệm cuối rồi cắt (VE có `frame_mask`, codec nhân quả ⇒ trùng kết quả T thật), ctx đệm tới L = 256 kèm mask.
///   Vượt bucket ⇒ `canRun == false` ⇒ engine chạy ORT, backend đếm phần lùi (`noteFallback`).
/// - prep (vị trí / nhúng t / bias mask) chạy ORT CPU 1 luồng; main + codec chạy Core ML EP (`MLComputeUnits =
///   CPUOnly`, `ModelCacheDirectory` = cache của gói). Trọng số nạp từ bộ nhớ (`WeightFile`) — né lỗi external data của
///   Core ML EP ORT 1.24.2.
/// - Session dựng **lười** ở lượt đầu cần bucket đó; giữ tối đa `sessionCap` session Core ML (cũ nhất bị nhả).
///
/// Engine gọi tuần tự trong khoá tổng hợp; `lock` để đọc thống kê / nhả session từ luồng khác (`VieNeuCoreMLReaderRoute`).
final class VieNeuCoreMLFlowBackend: VieNeuFlowBackend, @unchecked Sendable {
    typealias Tensor = VieNeuONNXProbeSession.Tensor

    enum BackendError: LocalizedError {
        case failure(String)

        var errorDescription: String? {
            switch self {
            case .failure(let message): return message
            }
        }
    }

    /// Số đo cộng dồn từ lần `resetStats` gần nhất (`VieNeuCoreMLReaderRoute.counters()` → `[NghiEnergy] Summary`).
    struct Stats: Sendable {
        var coreMLChunks = 0
        var fallbackChunks = 0
        /// Chunk Core ML lỗi rồi chạy lại bằng ORT (chỉ backend của trình đọc).
        var failures = 0
    }

    static let contextDim = 256
    static let samplesPerFrame = 1536
    /// Shape graph tĩnh đã đóng băng: style `[1, 50, 256]`, speaker `[1, 192]` (giọng có sẵn và giọng nhân bản đều vậy).
    static let styleRows = 50
    static let speakerDim = 192

    let package: VieNeuCoreMLPackage
    let manifest: VieNeuCoreMLPackage.Manifest
    /// Backend của trình đọc (P2c): lùi ORT khi lỗi, ghi log nạp / lượt đầu.
    let isReader: Bool
    let lock = NSLock() // internal: `+Reader` ghi tập session đã chạy lượt đầu
    /// Session đã chạy lượt đầu ("ve64", "codec128") — `+Reader` log thời gian lượt đầu một lần mỗi session.
    var firstRunDone: Set<String> = []
    private var sessionCap: Int
    private var preps: [Int: VieNeuONNXProbeSession] = [:]
    private var mains: [Int: VieNeuONNXProbeSession] = [:]
    private var codecs: [Int: VieNeuONNXProbeSession] = [:]
    /// Thứ tự dùng gần nhất của session Core ML ("ve64", "codec128"…), cũ nhất ở đầu.
    private var recency: [String] = []
    private var stats = Stats()

    init(package: VieNeuCoreMLPackage, manifest: VieNeuCoreMLPackage.Manifest, sessionCap: Int, isReader: Bool) {
        self.package = package
        self.manifest = manifest
        self.sessionCap = max(2, sessionCap)
        self.isReader = isReader
    }

    var fallsBackToORTOnError: Bool { isReader }

    func noteFailure(_ error: Error) {
        lock.lock()
        stats.failures += 1
        let count = stats.failures
        lock.unlock()
        AppLogger.shared.log("❌ [VieNeuCoreML] Chunk Core ML lỗi (\(count)), chạy lại bằng ORT: \(error.localizedDescription)")
    }

    var statsSnapshot: Stats {
        lock.lock(); defer { lock.unlock() }
        return stats
    }

    func resetStats() {
        lock.lock(); defer { lock.unlock() }
        stats = Stats()
    }

    /// Số session Core ML đang giữ (VE main + codec).
    var loadedSessionCount: Int {
        lock.lock(); defer { lock.unlock() }
        return recency.count
    }

    /// Nhả mọi session (giải phóng RAM của Core ML); lượt sau tự dựng lại từ cache.
    func releaseSessions() {
        lock.lock(); defer { lock.unlock() }
        preps.removeAll()
        mains.removeAll()
        codecs.removeAll()
        recency.removeAll()
    }

    func veBucket(for frames: Int) -> Int? { manifest.veBuckets.sorted().first { $0 >= frames } }
    func codecBucket(for frames: Int) -> Int? { manifest.codecBuckets.sorted().first { $0 >= frames } }

    // MARK: - VieNeuFlowBackend

    func canRun(_ request: VieNeuFlowRequest) -> Bool {
        fallbackReason(request) == nil
    }

    func noteFallback(_ request: VieNeuFlowRequest) {
        lock.lock(); defer { lock.unlock() }
        stats.fallbackChunks += 1
    }

    func trajectory(_ request: VieNeuFlowRequest) throws -> [Float] {
        guard let bucket = veBucket(for: request.frames) else { throw BackendError.failure("T \(request.frames) vượt bucket VE") }
        let started = ProcessInfo.processInfo.systemUptime
        let latent = try trajectory(request, veBucket: bucket)
        noteRun(key: "ve\(bucket)", started: started)
        lock.lock()
        stats.coreMLChunks += 1
        lock.unlock()
        return latent
    }

    func decode(latent: [Float], frames: Int, latentChannels: Int) throws -> [Float] {
        guard let bucket = codecBucket(for: frames) else { throw BackendError.failure("T \(frames) vượt bucket codec") }
        let started = ProcessInfo.processInfo.systemUptime
        let samples = try decode(latent: latent, frames: frames, latentChannels: latentChannels, codecBucket: bucket)
        noteRun(key: "codec\(bucket)", started: started)
        return samples
    }

    // MARK: - Chạy ở bucket chỉ định (tự kiểm dùng thẳng)

    /// Quỹ đạo ở bucket VE chỉ định (≥ T). Tự kiểm của bước chuẩn bị gọi với mọi bucket vừa với đoạn golden.
    func trajectory(_ request: VieNeuFlowRequest, veBucket bucket: Int) throws -> [Float] {
        let channels = request.latentChannels
        let length = manifest.lengthFrozen
        let (prep, main) = try veSessions(bucket: bucket)
        let context = Self.padContext(request.context, rows: request.contextLength, dim: request.contextDim, to: length)
        let contextMask = Self.padMask(request.mask, to: length)
        let nullRows = request.nullContextShape.count >= 2 ? Int(request.nullContextShape[1]) : 0
        let nullContext = Self.padContext(request.nullContext, rows: nullRows, dim: request.contextDim, to: length)
        let nullMask = Self.padMask(request.nullMask, to: length)
        var frameMask = [Float](repeating: 0, count: bucket)
        for index in 0..<min(request.frames, bucket) { frameMask[index] = 1 }

        var x = Self.pad(request.latent, channels: channels, frames: request.frames, bucket: bucket)
        let grid = request.grid
        for step in 0..<(grid.count - 1) {
            try Task.checkCancellation()
            let t = Float(grid[step])
            var velocity = try Self.velocity(
                prep: prep, main: main, x: x, t: t, frameMask: frameMask, context: context, contextMask: contextMask,
                speaker: request.speaker, style: request.style, request: request, bucket: bucket, length: length
            )
            if request.cfg > 0 {
                let unconditioned = try Self.velocity(
                    prep: prep, main: main, x: x, t: t, frameMask: frameMask, context: nullContext, contextMask: nullMask,
                    speaker: request.nullSpeaker, style: request.nullStyle, request: request, bucket: bucket, length: length
                )
                for index in velocity.indices {
                    velocity[index] = unconditioned[index] + request.cfg * (velocity[index] - unconditioned[index])
                }
            }
            let delta = Float(grid[step + 1] - grid[step])
            for index in x.indices { x[index] += delta * velocity[index] }
        }
        return Self.crop(x, channels: channels, frames: request.frames, bucket: bucket)
    }

    /// Codec ở bucket chỉ định (≥ T): đệm cuối, chạy, lấy `T × 1536` mẫu đầu.
    func decode(latent: [Float], frames: Int, latentChannels: Int, codecBucket bucket: Int) throws -> [Float] {
        let codec = try codecSession(bucket: bucket)
        let padded = Self.pad(latent, channels: latentChannels, frames: frames, bucket: bucket)
        let outputs = try codec.run(["x": Tensor(values: padded, shape: [1, Int64(latentChannels), Int64(bucket)])])
        guard let name = codec.outputNames.first, let samples = outputs[name]?.values else {
            throw BackendError.failure("codec_decoder không trả output")
        }
        return Array(samples.prefix(frames * Self.samplesPerFrame))
    }

    // MARK: - Session

    /// Dựng session Core ML / prep của một graph — bước chuẩn bị gọi để biên dịch, chạy nháp gọi để nạp sẵn; lượt đọc
    /// gọi lười qua `veSessions` / `codecSession`. Trả số ms dựng.
    @discardableResult
    func loadSession(kind: String, bucket: Int) throws -> Double {
        let started = ProcessInfo.processInfo.systemUptime
        switch kind {
        case "ve": _ = try veSessions(bucket: bucket)
        default: _ = try codecSession(bucket: bucket)
        }
        return (ProcessInfo.processInfo.systemUptime - started) * 1_000
    }

    /// Session dựng **ngoài** `lock` (Core ML biên dịch lần đầu mất vài chục giây — giữ khoá thì luồng khác đọc thống kê /
    /// nhả session bị treo theo). Engine gọi tuần tự nên không có hai lượt cùng dựng một bucket.
    private func veSessions(bucket: Int) throws -> (VieNeuONNXProbeSession, VieNeuONNXProbeSession) {
        let key = "ve\(bucket)"
        lock.lock()
        if let prep = preps[bucket], let main = mains[bucket] {
            touchLocked(key)
            lock.unlock()
            return (prep, main)
        }
        let existingPrep = preps[bucket]
        lock.unlock()
        let prep = try existingPrep ?? VieNeuONNXProbeSession(
            modelPath: package.url("ve_prep_T\(bucket).onnx").path, provider: "CPU", options: [:], threads: 1, logPath: ""
        )
        let main = try makeCoreMLSession("ve_main_T\(bucket).onnx", weights: manifest.veWeights)
        lock.lock()
        preps[bucket] = prep
        mains[bucket] = main
        touchLocked(key)
        trimLocked(keeping: key)
        lock.unlock()
        return (prep, main)
    }

    private func codecSession(bucket: Int) throws -> VieNeuONNXProbeSession {
        let key = "codec\(bucket)"
        lock.lock()
        if let codec = codecs[bucket] {
            touchLocked(key)
            lock.unlock()
            return codec
        }
        lock.unlock()
        let codec = try makeCoreMLSession("codec_T\(bucket).onnx", weights: manifest.codecWeights)
        lock.lock()
        codecs[bucket] = codec
        touchLocked(key)
        trimLocked(keeping: key)
        lock.unlock()
        return codec
    }

    private func makeCoreMLSession(_ name: String, weights: String) throws -> VieNeuONNXProbeSession {
        try FileManager.default.createDirectory(at: package.cacheDirectory, withIntermediateDirectories: true)
        return try VieNeuONNXProbeSession(
            modelPath: package.url(name).path,
            provider: "CoreML",
            options: Self.coreMLOptions(package: package),
            threads: 2,
            logPath: "",
            weights: [.init(name: weights, path: package.url(weights).path)]
        )
    }

    /// Tuỳ chọn Core ML EP của mọi session Core ML (lượt đọc, chạy nháp, bước chuẩn bị) — một chỗ, để bước chuẩn bị biên
    /// dịch đúng bản mà lượt đọc nạp lại từ cache.
    static func coreMLOptions(package: VieNeuCoreMLPackage) -> [String: String] {
        [
            "ModelFormat": "MLProgram",
            "MLComputeUnits": "CPUOnly",
            "RequireStaticInputShapes": "1",
            "ModelCacheDirectory": package.cacheDirectory.path
        ]
    }

    private func touchLocked(_ key: String) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    /// Nhả session dùng lâu nhất cho tới khi số session Core ML ≤ `sessionCap` (không nhả `keeping` — vừa dựng / đang dùng).
    private func trimLocked(keeping: String?) {
        while recency.count > sessionCap, let oldest = recency.first(where: { $0 != keeping }) {
            recency.removeAll { $0 == oldest }
            if oldest.hasPrefix("ve"), let bucket = Int(oldest.dropFirst(2)) {
                mains[bucket] = nil
            } else if let bucket = Int(oldest.dropFirst(5)) {
                codecs[bucket] = nil
            }
        }
    }

    private func fallbackReason(_ request: VieNeuFlowRequest) -> String? {
        if veBucket(for: request.frames) == nil || codecBucket(for: request.frames) == nil { return "T > \(manifest.veBuckets.max() ?? 0)" }
        if request.contextLength > manifest.lengthFrozen { return "L > \(manifest.lengthFrozen)" }
        if request.contextDim != Self.contextDim { return "D ≠ \(Self.contextDim)" }
        if request.styleRows != Self.styleRows || request.styleColumns != Self.contextDim
            || request.speaker.count != Self.speakerDim || request.nullSpeaker.count != Self.speakerDim {
            return "giọng khác dạng"
        }
        return nil
    }
}
