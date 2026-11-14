import Foundation

/// **TẠM — màn đo "Codec Turbo: AMX vs Neural Engine"** (hướng 3 báo cáo tối ưu Turbo §18, 1.3.932; anh Bửu duyệt
/// 2026-11-14). Một nút: so codec của audio.cpp (AMX qua Accelerate — đường trình đọc đang chạy) với graph codec MOSS
/// chính thức qua ONNX Runtime: CPU, Core ML CPU (fp32), Core ML + Neural Engine — **cùng mã âm thanh**. Xoá màn đo, file
/// này và `Caches/turbo-codec-bench/` khi có kết luận.
///
/// Cách đo:
/// 1. Tổng hợp 3 câu phiên âm cố định (32 / 64 / ~123 khung) × 3 vòng bằng `VieNeuTurboRuntime` với giọng Turbo đang chọn
///    (hoặc giọng Turbo đầu tiên đã tải): `codes_dump_file` lấy mã, `text_chunk_size=1000` để mỗi câu một lượt sinh, bộ
///    đếm giờ audio.cpp cho `codecMs` (AMX). Log app bật tạm trong lúc đo rồi trả về như cũ.
/// 2. Mỗi cấu hình ONNX: dựng session (Core ML: shape cố định bucket 64 / 128 khung, độn mã + `audio_code_lengths` thật),
///    một lượt nháp, rồi giải mã đủ 9 mẫu ⇒ ms mỗi giây tiếng + SNR so với tiếng audio.cpp (mono). Mỗi lúc chỉ giữ một
///    session (RAM).
/// 3. Ghi báo cáo Markdown (`TurboCodecBenchReport`) vào thư mục cache để chia sẻ.
final class TurboCodecBenchRunner: @unchecked Sendable {
    struct Sample {
        let round: Int
        let textIndex: Int
        let frames: Int
        let seconds: Double
        /// Mã xếp theo khung (`frames × 16`).
        let codes: [Int32]
        /// Tiếng audio.cpp (mono 48 kHz) — chuẩn để so.
        let reference: [Float]
        /// `speech_decoder_ms` của audio.cpp (AMX); `nil` khi bộ đếm giờ không chạy.
        let amxCodecMs: Double?
        let thermal: ProcessInfo.ThermalState
    }

    struct ConfigResult {
        let label: String
        /// Dựng session theo bucket (Core ML: gồm biên dịch lần đầu; lần sau nạp từ cache).
        var createMs: [Int: Double] = [:]
        var firstRunMs: [Int: Double] = [:]
        /// Đọc từ log của ORT: "nhận X/Y node, Z mảnh" theo bucket.
        var coverage: [Int: String] = [:]
        /// ms mỗi giây tiếng và SNR theo mẫu (cùng thứ tự `samples`).
        var msPerSecond: [Double?] = []
        var snr: [Double?] = []
        var errors: [String] = []
    }

    /// Câu mẫu đã phiên âm sea-g2p (câu ví dụ của audio.cpp) — độ dài khung chỉ phụ thuộc số lần lặp.
    static let sentence = "sˈin tʃˈaː2w tˈeɜ zˈəːɜj. ɗˈəɪ lˌaː2 bˈaː4n tˈy4 ŋˈiɛ6m."
    static let texts = [sentence, Array(repeating: sentence, count: 2).joined(separator: " "),
                        Array(repeating: sentence, count: 4).joined(separator: " ")]
    static let rounds = 3
    static let buckets = [64, 128]

    private let queue = DispatchQueue(label: "TurboCodecBench", qos: .userInitiated)

    /// Chạy trọn phép đo; trả nội dung báo cáo + file đã ghi.
    func run(progress: @escaping @Sendable (String) -> Void) async throws -> (text: String, url: URL) {
        let started = Date()
        let thermalStart = ProcessInfo.processInfo.thermalState
        // Runtime Turbo dùng chung với trình đọc ⇒ đang đọc thì số đo lẫn lượt của trình đọc.
        if await MainActor.run(body: { TTSManager.shared.isPlaying }) {
            throw TurboCodecProbeSession.ProbeError(message: "Hãy dừng đọc truyện trước khi đo")
        }
        let store = try VieNeuTurboModelStore()
        guard store.hasModel else { throw TurboCodecProbeSession.ProbeError(message: "Chưa tải model Turbo") }
        guard let voiceId = Self.pickVoice(store: store) else {
            throw TurboCodecProbeSession.ProbeError(message: "Chưa có giọng Turbo nào đã tải")
        }
        try await TurboCodecBenchAssets.ensureDownloaded(progress: progress)

        progress("Đang nạp Turbo…")
        _ = try await VieNeuTurboRuntime.shared.prepare(modelURL: store.modelURL, threads: VieNeuTurboTTSService.threadCount)
        let samples = try await synthesizeSamples(store: store, voiceId: voiceId, progress: progress)

        var results: [ConfigResult] = []
        let configs: [(TurboCodecProbeSession.Provider, Bool)] = [
            (.cpu, false),
            (.coreML(computeUnits: "CPUOnly"), true),
            (.coreML(computeUnits: "CPUAndNeuralEngine"), true)
        ]
        for (provider, usesBuckets) in configs {
            results.append(await evaluate(provider: provider, usesBuckets: usesBuckets, samples: samples, progress: progress))
        }

        let text = TurboCodecBenchReport.make(
            started: started,
            thermalStart: thermalStart,
            thermalEnd: ProcessInfo.processInfo.thermalState,
            voiceId: voiceId,
            samples: samples,
            results: results
        )
        let url = TurboCodecBenchAssets.directory.appendingPathComponent("bao-cao-codec-turbo-\(Int(started.timeIntervalSince1970)).md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return (text, url)
    }

    // MARK: - Tổng hợp mẫu (audio.cpp, AMX)

    private func synthesizeSamples(
        store: VieNeuTurboModelStore,
        voiceId: String,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> [Sample] {
        let logger = AppLogger.shared
        let loggingWasOn = logger.isLoggingEnabled
        logger.isLoggingEnabled = true  // bộ đếm giờ của audio.cpp chỉ chạy khi log bật
        defer { logger.isLoggingEnabled = loggingWasOn }
        let codesURL = TurboCodecBenchAssets.directory.appendingPathComponent("codes.txt")
        var samples: [Sample] = []
        for round in 1...Self.rounds {
            for (index, text) in Self.texts.enumerated() {
                progress("Turbo (AMX) vòng \(round)/\(Self.rounds), câu \(index + 1)/\(Self.texts.count)…")
                try? FileManager.default.removeItem(at: codesURL)
                let output = try await VieNeuTurboRuntime.shared.synthesize(
                    phonemes: text,
                    referenceCodesURL: store.referenceCodesURL(voiceId: voiceId),
                    speakerEmbeddingURL: store.speakerEmbeddingURL(voiceId: voiceId),
                    qos: .userInitiated,
                    extraRequestOptions: [("codes_dump_file", codesURL.path), ("text_chunk_size", "1000")]
                )
                let (frames, codes) = try Self.readCodes(codesURL)
                samples.append(Sample(
                    round: round,
                    textIndex: index,
                    frames: frames,
                    seconds: Double(output.samples.count) / Double(max(1, output.sampleRate)),
                    codes: codes,
                    reference: output.samples,
                    amxCodecMs: output.timings.map(\.codecMs),
                    thermal: ProcessInfo.processInfo.thermalState
                ))
            }
        }
        return samples
    }

    /// Dòng `generated_codes <khung> <nhóm> <mã…>` cuối cùng (mỗi câu một lượt sinh).
    static func readCodes(_ url: URL) throws -> (Int, [Int32]) {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard let line = text.split(separator: "\n").last(where: { $0.hasPrefix("generated_codes ") }) else {
            throw TurboCodecProbeSession.ProbeError(message: "audio.cpp không ghi mã âm thanh")
        }
        let parts = line.split(separator: " ")
        guard parts.count > 3, let frames = Int(parts[1]), let groups = Int(parts[2]), groups == 16,
              parts.count == 3 + frames * groups else {
            throw TurboCodecProbeSession.ProbeError(message: "dòng mã âm thanh sai dạng")
        }
        return (frames, parts.dropFirst(3).compactMap { Int32($0) })
    }

    // MARK: - Giải mã bằng ONNX

    private func evaluate(
        provider: TurboCodecProbeSession.Provider,
        usesBuckets: Bool,
        samples: [Sample],
        progress: @escaping @Sendable (String) -> Void
    ) async -> ConfigResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<ConfigResult, Never>) in
            queue.async {
                continuation.resume(returning: Self.evaluateLocked(
                    provider: provider, usesBuckets: usesBuckets, samples: samples, progress: progress
                ))
            }
        }
    }

    private static func evaluateLocked(
        provider: TurboCodecProbeSession.Provider,
        usesBuckets: Bool,
        samples: [Sample],
        progress: @escaping @Sendable (String) -> Void
    ) -> ConfigResult {
        var result = ConfigResult(label: provider.label)
        result.msPerSecond = Array(repeating: nil, count: samples.count)
        result.snr = Array(repeating: nil, count: samples.count)
        // Nhóm mẫu theo bucket (shape động ⇒ một nhóm).
        var groups: [(bucket: Int?, indices: [Int])] = []
        if usesBuckets {
            var lower = 0
            for bucket in buckets {
                let indices = samples.indices.filter { samples[$0].frames > lower && samples[$0].frames <= bucket }
                groups.append((bucket: bucket, indices: indices))
                lower = bucket
            }
        } else {
            groups.append((bucket: nil, indices: Array(samples.indices)))
        }
        for group in groups where !group.indices.isEmpty {
            let key = group.bucket ?? 0
            progress("\(provider.label)\(group.bucket.map { " · \($0) khung" } ?? ""): dựng session…")
            let logURL = TurboCodecBenchAssets.directory.appendingPathComponent("ort-\(key).log")
            let createStarted = ProcessInfo.processInfo.systemUptime
            let session: TurboCodecProbeSession
            do {
                session = try TurboCodecProbeSession(
                    modelURL: TurboCodecBenchAssets.modelURL,
                    weightName: TurboCodecBenchAssets.weightFileName,
                    weightURL: TurboCodecBenchAssets.weightURL,
                    provider: provider,
                    bucket: group.bucket,
                    cacheDirectory: TurboCodecBenchAssets.coreMLCacheDirectory,
                    logURL: logURL
                )
            } catch {
                result.errors.append("\(key) khung: dựng session lỗi — \(error.localizedDescription)")
                continue
            }
            result.createMs[key] = (ProcessInfo.processInfo.systemUptime - createStarted) * 1_000
            result.coverage[key] = coverage(logURL: logURL)
            for (order, index) in group.indices.enumerated() {
                let sample = samples[index]
                progress("\(provider.label): giải mã \(order + 1)/\(group.indices.count)…")
                do {
                    if order == 0 {
                        let warm = ProcessInfo.processInfo.systemUptime
                        _ = try session.decode(codes: sample.codes, frames: sample.frames)
                        result.firstRunMs[key] = (ProcessInfo.processInfo.systemUptime - warm) * 1_000
                    }
                    let begin = ProcessInfo.processInfo.systemUptime
                    let audio = try session.decode(codes: sample.codes, frames: sample.frames)
                    let ms = (ProcessInfo.processInfo.systemUptime - begin) * 1_000
                    result.msPerSecond[index] = ms / max(0.001, sample.seconds)
                    result.snr[index] = snrDB(audio.mono, sample.reference)
                } catch {
                    result.errors.append("\(key) khung, mẫu \(index + 1): \(error.localizedDescription)")
                }
            }
        }
        return result
    }

    /// SNR (dB) của `test` so với `reference` trên đoạn chung.
    static func snrDB(_ test: [Float], _ reference: [Float]) -> Double {
        let count = min(test.count, reference.count)
        guard count > 0 else { return -.infinity }
        var signal = 0.0
        var noise = 0.0
        for index in 0..<count {
            let ref = Double(reference[index])
            let diff = Double(test[index]) - ref
            signal += ref * ref
            noise += diff * diff
        }
        return 10 * log10(signal / max(noise, 1e-30))
    }

    /// "nhận 714/907 node, 14 mảnh" từ log INFO của ORT (Core ML EP); CPU ⇒ "—".
    static func coverage(logURL: URL) -> String {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return "—" }
        func last(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.matches(in: text, range: range).last,
                  let captured = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captured])
        }
        guard let total = last("number of nodes in the graph: (\\d+)"),
              let supported = last("number of nodes supported by CoreML: (\\d+)") else { return "—" }
        let partitions = last("number of partitions supported by CoreML: (\\d+)") ?? "?"
        return "\(supported)/\(total) node, \(partitions) mảnh"
    }

    /// Giọng Turbo đang chọn nếu đã tải; không thì giọng Turbo đầu tiên có đủ file.
    static func pickVoice(store: VieNeuTurboModelStore) -> String? {
        let selection = VieNeuVoiceSelection.stored
        if selection.model == .turbo, store.hasVoice(voiceId: selection.voiceId) { return selection.voiceId }
        let fileManager = FileManager.default
        for directory in [store.voicesURL, store.customVoicesURL] {
            let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
            if let found = names.sorted().first(where: { store.hasVoice(voiceId: $0) }) { return found }
        }
        return nil
    }
}
