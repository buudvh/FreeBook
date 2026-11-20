import Foundation

/// Trình đọc **vtts Việt–Anh (Offline)** — `LocalTTSEngine` cho `tool == "vtts"`. Model C99 siêu nhẹ (2,6 MB mỗi giọng,
/// release v0.4.0 của https://github.com/tuanpmt/vtts, đóng sẵn trong IPA) đọc tiếng Việt, tiếng Anh và câu trộn:
/// front-end của vtts chọn ngôn ngữ theo **từng từ** (chế độ `auto`, tiếng Anh tra từ điển VLEX dựng từ CMUdict) và tự
/// chuẩn hoá số / ngày / giờ ⇒ không đi qua `TextPreprocessor` của NghiTTS.
///
/// ## Cùng hợp đồng với NghiTTS / VieNeu
/// - Đi qua `PiperSynthesisCoordinator` ⇒ 4 mức ưu tiên, gộp theo `synthesisKey`, mỗi lúc một lượt tổng hợp. Lượt bị
///   huỷ dừng trước chunk front-end kế tiếp (thẻ huỷ của `VttsRuntime`) và ném `CancellationError` — không ghi lỗi.
/// - **Không có tốc độ tổng hợp**: tham số `speed` bị bỏ qua, luôn tổng hợp `length_scale = 1`; tốc độ nghe do
///   `NghiAudioPlayerQueue` lo như VieNeu (đổi tốc độ không phải tổng hợp lại).
/// - Khoảng lặng đuôi theo `boundaryKind`: `VieNeuTTSEngine.pauseSeconds(for:)` — cùng khoá `*PauseDuration` và mặc định
///   với NghiTTS, không chia theo tốc độ (như Turbo). Giữa các câu trong đoạn: 150 ms của vtts (`VTTS_CHUNK_GAP_MS`).
/// - Chữ tới đây đã qua `TTSReplacementManager` ở tầng trên. Ở đây chỉ áp "Phiên âm tiếng Nhật" của **chính** trình đọc
///   (`TTSJapaneseTextTransliterator`, khoá `ttsJapaneseTransliterationEnabled.vtts`, chưa có khoá ⇒ tắt) — ở tầng service
///   để giọng dự phòng nhận chữ gốc (`tts.md`) — rồi chuẩn hoá NFC: chữ lấy từ web đôi khi ở dạng NFD (dấu tách rời),
///   front-end C so từng code point.
/// - Âm lượng mỗi đoạn kéo về mốc −16 dBFS lúc có tiếng (`VttsLoudness`, 1.3.1033) — model xuất nhỏ.
/// - WAV PCM16 mono ở tần số của model (22 050 Hz); `pcmDuration` gồm khoảng lặng đuôi; RTF (`TTSEngineRTFStore`) chia
///   cho phần lời đọc.
final class VttsTTSService: LocalTTSEngine, @unchecked Sendable {
    static let shared = VttsTTSService()

    /// Giá trị `TTSManager.tool` của trình đọc này — cũng là hậu tố khoá cài đặt theo trình đọc (phiên âm tiếng Nhật…).
    static let tool = "vtts"
    /// Tần số của các giọng vi-en — dùng cho đoạn im lặng tự sinh (không cần nạp model).
    static let sampleRate = 22_050

    private let runtime = VttsRuntime.shared

    private init() {}

    /// Đủ tài sản trong bundle (2 model + từ điển). Chỉ kiểm file ⇒ gọi được từ main.
    var isAvailable: Bool { VttsRuntime.isAvailable }

    var engineStatus: String {
        "vtts v0.4 (C99, Việt + Anh, 22 kHz, CPU 1 luồng)"
    }

    /// Nạp handle của giọng (mmap model + từ điển) — đoạn đầu không phải chờ. Idempotent.
    func prepare(voice: String) async throws {
        guard isAvailable else { throw VttsRuntime.Failure.missingAssets }
        try await runtime.prepare(voice: VttsVoice.resolve(voice))
    }

    /// Nhả handle của mọi giọng (khi trình đọc rời vtts). Không chặn — gọi được từ main.
    func releaseRuntime() {
        runtime.releaseAll()
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
        let resolved = VttsVoice.resolve(voice)
        let effectiveKey = synthesisKey ?? Self.makeDefaultSynthesisKey(text: text, voice: resolved, boundaryKind: boundaryKind)
        let payload = try await PiperSynthesisCoordinator.shared.enqueuePayload(
            priority: priority,
            requestID: requestID,
            synthesisKey: effectiveKey
        ) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.executeInternalSynthesis(text: text, voice: resolved, boundaryKind: boundaryKind)
        }
        return (
            data: payload.data,
            pcmDuration: payload.pcmDuration,
            queueWaitMs: payload.queueWaitMs,
            synthesisMs: payload.synthesisMs
        )
    }

    private func executeInternalSynthesis(
        text: String,
        voice: VttsVoice,
        boundaryKind: TTSBoundaryKind
    ) async throws -> PiperSynthesisPayload {
        if PiperTTSService.isUnspeakable(text) { return Self.silencePayload(text: text) }
        guard isAvailable else {
            AppLogger.shared.log("❌ [Vtts] Bản build thiếu tài sản vtts (thư mục \(VttsRuntime.assetSubdirectory)/ trong bundle)")
            throw VttsRuntime.Failure.missingAssets
        }
        let spoken = TTSJapaneseTextTransliterator.apply(text, tool: Self.tool).precomposedStringWithCanonicalMapping
        try Task.checkCancellation()

        let started = ProcessInfo.processInfo.systemUptime
        let output = try await runtime.synthesize(text: spoken, voice: voice, lengthScale: 1)
        // Front-end không ra chunk nào (chỉ ký hiệu vtts không đọc) ⇒ im lặng theo khuôn chung, không phải lỗi.
        guard !output.samples.isEmpty else { return Self.silencePayload(text: text) }

        let sampleRate = max(1, output.sampleRate)
        let pause = VieNeuTTSEngine.pauseSeconds(for: boundaryKind)
        var samples = output.samples
        // Model xuất nhỏ (đo CI: nu-10 −24 dBFS, nam-1 −20 dBFS lúc có tiếng) ⇒ kéo về mốc chung trước khi nối khoảng lặng.
        let gainDb = VttsLoudness.normalize(&samples, sampleRate: sampleRate, fallbackGainDb: voice.defaultLoudnessGainDb)
        samples.append(contentsOf: repeatElement(Float(0), count: Int(Double(sampleRate) * pause)))
        let synthesisMs = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        let speechSeconds = Double(output.samples.count) / Double(sampleRate)
        let pcmDuration = Double(samples.count) / Double(sampleRate)
        TTSEngineRTFStore.shared.record(text: text, synthesisMs: synthesisMs, speechSeconds: speechSeconds)
        Self.logChunk(
            text: text, voice: voice, output: output, synthesisMs: synthesisMs, speechSeconds: speechSeconds,
            pause: pause, gainDb: gainDb, boundaryKind: boundaryKind
        )
        return PiperSynthesisPayload(
            data: WAVEncoder.encodePCM16(samples: samples, sampleRate: sampleRate, channels: 1),
            pcmDuration: pcmDuration,
            speechDuration: speechSeconds,
            synthesisMs: synthesisMs
        )
    }

    /// Một dòng mỗi đoạn: số ký tự, số câu (chunk front-end), ms trong C / cả lượt, giây tiếng, RTF, nhiệt.
    private static func logChunk(
        text: String,
        voice: VttsVoice,
        output: VttsRuntime.Output,
        synthesisMs: Double,
        speechSeconds: Double,
        pause: Double,
        gainDb: Float,
        boundaryKind: TTSBoundaryKind
    ) {
        let rtf = speechSeconds > 0.001 ? String(format: "%.3f", synthesisMs / 1_000 / speechSeconds) : "—"
        let fields: [String] = [
            "voice=\(voice.rawValue)",
            "chars=\(text.count)",
            "chunks=\(output.chunkCount)",
            String(format: "runMs=%.0f", output.runMs),
            String(format: "synthMs=%.0f", synthesisMs),
            String(format: "audio=%.2fs", speechSeconds),
            String(format: "pause=%.2fs", pause),
            String(format: "gain=+%.1fdB", gainDb),
            "RTF=\(rtf)",
            "boundary=\(boundaryKind.rawValue)",
            "thermal=\(ProcessInfo.processInfo.thermalState.rawValue)"
        ]
        AppLogger.shared.log("🗣️ [Vtts] Đoạn: " + fields.joined(separator: " "))
    }

    private static func silencePayload(text: String) -> PiperSynthesisPayload {
        let spec = PiperTTSService.makeSilenceSpec(text: text, speed: 1.0, sampleRate: sampleRate)
        let data = WAVEncoder.encodePCM16(samples: spec.samples, sampleRate: spec.sampleRate, channels: 1)
        return PiperSynthesisPayload(data: data, pcmDuration: spec.pcmDuration, speechDuration: 0)
    }

    /// Key mặc định khi caller bỏ trống — khuôn `auto-<digest>` như VieNeu, tiền tố `vtts` ⇒ không trùng khoá của engine
    /// khác trong `PiperSynthesisCoordinator` dùng chung. Không có tốc độ: vtts luôn tổng hợp 1×.
    private static func makeDefaultSynthesisKey(text: String, voice: VttsVoice, boundaryKind: TTSBoundaryKind) -> String {
        let raw = "vtts|\(voice.rawValue)|\(boundaryKind.rawValue)|\(text)"
        var hash: UInt64 = 5381
        for byte in raw.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return "auto-\(String(hash, radix: 16))"
    }
}
