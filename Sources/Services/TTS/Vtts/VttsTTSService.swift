import Foundation

/// Trình đọc **vtts Việt–Anh (Offline)** — `LocalTTSEngine` cho `tool == "vtts"`. Model C99 siêu nhẹ (2,6 MB mỗi giọng,
/// release v0.4.0 của https://github.com/tuanpmt/vtts, đóng sẵn trong IPA) đọc tiếng Việt, tiếng Anh và câu trộn:
/// front-end của vtts chọn ngôn ngữ theo **từng từ** (chế độ `auto`, tiếng Anh tra từ điển VLEX dựng từ CMUdict) và tự
/// chuẩn hoá số / ngày / giờ ⇒ không đi qua `TextPreprocessor` của NghiTTS.
///
/// ## Cùng hợp đồng với NghiTTS / VieNeu
/// - Đi qua `PiperSynthesisCoordinator` ⇒ 4 mức ưu tiên, gộp theo `synthesisKey`, mỗi lúc một lượt tổng hợp. Lượt bị
///   huỷ dừng trước chunk front-end kế tiếp (thẻ huỷ của `VttsRuntime`) và ném `CancellationError` — không ghi lỗi.
/// - **Tự đọc nhanh** (1.3.1036): `speed` = tốc độ tạo tiếng (`TTSManager.localSynthesisSpeed`, kẹp `nativeSpeedRange`)
///   ⇒ `length_scale = 1 / speed`; `NghiAudioPlayerQueue` chỉ kéo phần vượt 2,0× (`TTSManager.localPlaybackRate`). Trước
///   đó luôn tổng hợp 1× rồi để `AVAudioPlayer` kéo nhanh — anh Bửu nghe ở 1,8× thấy tiếng "vụt" ở chỗ vtts nối mảnh, bản
///   tạo tiếng nhanh từ gốc thì hết.
/// - Khoảng lặng đuôi theo `boundaryKind`: `VieNeuTTSEngine.pauseSeconds(for:)` — cùng khoá `*PauseDuration` và mặc định
///   với NghiTTS — **chia cho tốc độ tạo tiếng** (như Nano) để nhịp giữ như lúc trình phát kéo cả đoạn. Giữa các câu trong
///   đoạn: 150 ms của vtts (`VTTS_CHUNK_GAP_MS`, không đổi theo tốc độ).
/// - Chữ tới đây đã qua `TTSReplacementManager` ở tầng trên. Ở đây chỉ áp "Phiên âm tiếng Nhật" của **chính** trình đọc
///   (`TTSJapaneseTextTransliterator`, khoá `ttsJapaneseTransliterationEnabled.vtts`, chưa có khoá ⇒ tắt; log `jp=` từ
///   1.3.1037) — ở tầng service
///   để giọng dự phòng nhận chữ gốc (`tts.md`) — rồi chuẩn hoá NFC: chữ lấy từ web đôi khi ở dạng NFD (dấu tách rời),
///   front-end C so từng code point.
/// - Đuôi cụt ở chỗ vtts nối mảnh làm nhỏ dần (`VttsEdgeFade`), rồi chỉnh tiếng + kéo mức + ghìm đỉnh (`VttsLoudness`,
///   "bản 4" anh Bửu chọn, 1.3.1036) — model xuất nhỏ và đục.
/// - WAV PCM16 mono ở tần số của model (22 050 Hz); `pcmDuration` gồm khoảng lặng đuôi; RTF (`TTSEngineRTFStore`) chia
///   cho phần lời đọc.
final class VttsTTSService: LocalTTSEngine, @unchecked Sendable {
    static let shared = VttsTTSService()

    /// Giá trị `TTSManager.tool` của trình đọc này — cũng là hậu tố khoá cài đặt theo trình đọc (phiên âm tiếng Nhật…).
    static let tool = "vtts"
    /// Tần số của các giọng vi-en — dùng cho đoạn im lặng tự sinh (không cần nạp model).
    static let sampleRate = 22_050

    /// Dải tốc độ vtts tự đọc (1.3.1036). Trên 2,0× chưa thử tai ⇒ phần vượt để trình phát kéo; dưới 1,0× giữ cách cũ
    /// (trình phát kéo chậm) — chưa có lý do đổi.
    static let nativeSpeedRange: ClosedRange<Double> = 1.0...2.0

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
        let nativeSpeed = Self.clampedNativeSpeed(speed)
        let effectiveKey = synthesisKey ?? Self.makeDefaultSynthesisKey(
            text: text, voice: resolved, speed: nativeSpeed, boundaryKind: boundaryKind
        )
        let payload = try await PiperSynthesisCoordinator.shared.enqueuePayload(
            priority: priority,
            requestID: requestID,
            synthesisKey: effectiveKey
        ) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.executeInternalSynthesis(
                text: text, voice: resolved, speed: nativeSpeed, boundaryKind: boundaryKind
            )
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
        speed: Double,
        boundaryKind: TTSBoundaryKind
    ) async throws -> PiperSynthesisPayload {
        if PiperTTSService.isUnspeakable(text) { return Self.silencePayload(text: text) }
        guard isAvailable else {
            AppLogger.shared.log("❌ [Vtts] Bản build thiếu tài sản vtts (thư mục \(VttsRuntime.assetSubdirectory)/ trong bundle)")
            throw VttsRuntime.Failure.missingAssets
        }
        let japanese = TTSJapaneseTextTransliterator.applyReportingChanges(text, tool: Self.tool)
        let spoken = japanese.text.precomposedStringWithCanonicalMapping
        try Task.checkCancellation()

        let started = ProcessInfo.processInfo.systemUptime
        let output = try await runtime.synthesize(text: spoken, voice: voice, lengthScale: Float(1 / speed))
        // Front-end không ra chunk nào (chỉ ký hiệu vtts không đọc) ⇒ im lặng theo khuôn chung, không phải lỗi.
        guard !output.samples.isEmpty else { return Self.silencePayload(text: text) }

        let sampleRate = max(1, output.sampleRate)
        let pause = VieNeuTTSEngine.pauseSeconds(for: boundaryKind) / speed
        var samples = output.samples
        // Đuôi cụt ở chỗ nối mảnh ⇒ nhỏ dần; rồi bản 4 (chỉnh tiếng, kéo mức, ghìm đỉnh) — đều trước khi nối khoảng lặng.
        let abruptEdges = VttsEdgeFade.apply(&samples, sampleRate: sampleRate)
        let loudness = VttsLoudness.process(&samples, sampleRate: sampleRate, fallbackGainDb: voice.defaultLoudnessGainDb)
        samples.append(contentsOf: repeatElement(Float(0), count: Int(Double(sampleRate) * pause)))
        let synthesisMs = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        let speechSeconds = Double(output.samples.count) / Double(sampleRate)
        let pcmDuration = Double(samples.count) / Double(sampleRate)
        TTSEngineRTFStore.shared.record(text: text, synthesisMs: synthesisMs, speechSeconds: speechSeconds)
        Self.logChunk(
            text: text, voice: voice, output: output, synthesisMs: synthesisMs, speechSeconds: speechSeconds,
            speed: speed, pause: pause, loudness: loudness, abruptEdges: abruptEdges,
            japanese: Self.japaneseLogField(isEnabled: japanese.isEnabled, changes: japanese.changes), boundaryKind: boundaryKind
        )
        return PiperSynthesisPayload(
            data: WAVEncoder.encodePCM16(samples: samples, sampleRate: sampleRate, channels: 1),
            pcmDuration: pcmDuration,
            speechDuration: speechSeconds,
            synthesisMs: synthesisMs
        )
    }

    /// Một dòng mỗi đoạn: số ký tự, số câu (chunk front-end), ms trong C / cả lượt, giây tiếng, tốc độ tạo tiếng, mức tăng /
    /// ghìm, số chỗ cụt đã làm nhỏ dần, RTF, nhiệt.
    private static func logChunk(
        text: String,
        voice: VttsVoice,
        output: VttsRuntime.Output,
        synthesisMs: Double,
        speechSeconds: Double,
        speed: Double,
        pause: Double,
        loudness: VttsLoudness.Result,
        abruptEdges: Int,
        japanese: String,
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
            String(format: "speed=%.2f", speed),
            String(format: "pause=%.2fs", pause),
            String(format: "gain=+%.1fdB", loudness.gainDb),
            String(format: "limit=%.1fdB", loudness.limitDb),
            "cut=\(abruptEdges)",
            japanese,
            "RTF=\(rtf)",
            "boundary=\(boundaryKind.rawValue)",
            "thermal=\(ProcessInfo.processInfo.thermalState.rawValue)"
        ]
        AppLogger.shared.log("🗣️ [Vtts] Đoạn: " + fields.joined(separator: " "))
    }

    /// `jp=off` | `jp=on(0)` | `jp=on(3: Konoha→Kô nô ha, Naruto→Na ru tô)` — công tắc "Phiên âm tiếng Nhật" của vtts và
    /// tối đa 2 cặp đã đổi (mỗi cặp ≤ 40 ký tự), không ghi cả đoạn chữ (1.3.1037).
    private static func japaneseLogField(isEnabled: Bool, changes: [String]) -> String {
        guard isEnabled else { return "jp=off" }
        guard !changes.isEmpty else { return "jp=on(0)" }
        let samples = changes.prefix(2).map { String($0.prefix(40)) }.joined(separator: ", ")
        return "jp=on(\(changes.count): \(samples))"
    }

    private static func silencePayload(text: String) -> PiperSynthesisPayload {
        let spec = PiperTTSService.makeSilenceSpec(text: text, speed: 1.0, sampleRate: sampleRate)
        let data = WAVEncoder.encodePCM16(samples: spec.samples, sampleRate: spec.sampleRate, channels: 1)
        return PiperSynthesisPayload(data: data, pcmDuration: spec.pcmDuration, speechDuration: 0)
    }

    /// Tốc độ tạo tiếng hợp lệ: kẹp `nativeSpeedRange`, giá trị lạ (≤ 0, NaN) ⇒ 1×.
    static func clampedNativeSpeed(_ speed: Double) -> Double {
        guard speed.isFinite, speed > 0 else { return 1 }
        return min(nativeSpeedRange.upperBound, max(nativeSpeedRange.lowerBound, speed))
    }

    /// Key mặc định khi caller bỏ trống — khuôn `auto-<digest>` như VieNeu, tiền tố `vtts` ⇒ không trùng khoá của engine
    /// khác trong `PiperSynthesisCoordinator` dùng chung. Có tốc độ tạo tiếng (1.3.1036) ⇒ tiếng 1× và 1,8× không lẫn nhau.
    private static func makeDefaultSynthesisKey(
        text: String,
        voice: VttsVoice,
        speed: Double,
        boundaryKind: TTSBoundaryKind
    ) -> String {
        let raw = "vtts|\(voice.rawValue)|\(String(format: "%.2f", speed))|\(boundaryKind.rawValue)|\(text)"
        var hash: UInt64 = 5381
        for byte in raw.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return "auto-\(String(hash, radix: 16))"
    }
}
