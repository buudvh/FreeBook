import Foundation

/// Engine **đọc lai Nano · Turbo** (1.3.934) — `LocalTTSEngine` mà `TTSManager.localEngine` trả khi
/// `VieNeuHybridRouting.context(voice:)` khác `nil`. Mỗi lượt tổng hợp: quyết model (`VieNeuHybridRouting.decide`), đổi
/// sang giọng cặp, gọi đúng service, khớp âm lượng đoạn của model phụ.
///
/// ## Vì sao bọc ở `localEngine`
/// Mọi lối tổng hợp của trình đọc (refill, đoạn đang phát, chương kế, prefix chương kế, warm-up) lấy engine qua đúng một
/// chỗ đó ⇒ không đụng `TTSManager.swift`, không đụng đường cắt đoạn / highlight. Hai service con giữ nguyên hợp đồng:
/// cùng `PiperSynthesisCoordinator` (mỗi lúc một lượt), cùng khoá tổng hợp do tầng trên tính (`synthesisKey` có model
/// của đoạn — `VieNeuModelChoice.synthesisEngineIdentity`).
///
/// ## Nạp model
/// `prepare` nạp model chính và **nhả model kia** (bắt đầu gọn RAM). Model phụ nạp lười ở đoạn đầu tiên cần nó rồi giữ
/// (hai service không còn tự nhả nhau khi đang đọc lai) — truyện không có đoạn nào cần thì không bao giờ nạp.
///
/// ## Tốc độ
/// Giọng Nano (A): đoạn Turbo tổng hợp 1×, hàng đợi phát nhân tốc độ tổng hợp của Nano (`playbackRateFactor`). Giọng Turbo
/// (B): đoạn Nano nhận `speed` của tầng trên — đang là 1,0 vì model hiệu lực là Turbo (`localSynthesisSpeed`).
final class VieNeuHybridTTSService: LocalTTSEngine, @unchecked Sendable {
    enum HybridError: LocalizedError {
        case engineUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .engineUnavailable(let name): return "Không dựng được engine VieNeu \(name) để đọc lai."
            }
        }
    }

    static let shared = VieNeuHybridTTSService()

    private let lock = NSLock()
    private var lastModel: VieNeuModelChoice?
    /// Model chính của lần `prepare` trước — chỉ nhả model phụ khi model chính đổi (hoặc lần đầu). `prepare` còn chạy khi
    /// đổi giọng cùng model, đóng sheet thử giọng, tải xong model…; nhả mỗi lần như thế là đang nóng (giọng Turbo, đọc Nano)
    /// mà bị nhả Nano ⇒ đoạn kế nạp lại ORT + Core ML đúng lúc máy nóng.
    private var preparedBase: VieNeuModelChoice?
    private let loudness = VieNeuHybridLoudness()

    var engineStatus: String {
        "VieNeu-TTS v3 đọc lai Nano (24 kHz) + Turbo (48 kHz)"
    }

    // MARK: - Chuẩn bị

    func prepare(voice: String) async throws {
        await VieNeuForeignTextClassifier.shared.refreshJapaneseDictionary()
        let context = VieNeuHybridRouting.context(voice: voice)
        let releasesOther = beginPrepare(baseModel: context?.baseModel)
        guard let context else {
            // Vừa mất cặp (xoá giọng / tắt công tắc) ⇒ chuẩn bị như đường thường.
            try await Self.service(for: VieNeuModelChoice.current).prepare(voice: voice)
            return
        }
        switch context.baseModel {
        case .nano:
            if releasesOther { await VieNeuTurboTTSService.releaseForNano() }
            try await Self.service(for: .nano).prepare(voice: context.pair.nanoVoice)
        case .turbo:
            if releasesOther { await VieNeuTurboTTSService.releaseNanoEngineIfLoaded() }
            try await Self.service(for: .turbo).prepare(voice: context.pair.turboVoiceId)
        }
        AppLogger.shared.log(
            "🔀 [VieNeuHybrid] Đọc lai sẵn sàng: model chính \(context.baseModel.label), cặp giọng "
                + "\(context.pair.nanoVoice) (Nano) ↔ \(context.pair.turboVoiceId) (Turbo)"
                + (context.pair.isCustom ? " · nhân bản" : " · có sẵn") + " — \(ProcessMemoryProbe.snapshot().summary)"
        )
    }

    // MARK: - Tổng hợp

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
            text: text, voice: voice, speed: speed, boundaryKind: boundaryKind,
            priority: priority, requestID: requestID, synthesisKey: synthesisKey
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
        guard let context = VieNeuHybridRouting.context(voice: voice) else {
            // Công tắc vừa tắt / cặp vừa mất giữa chừng ⇒ đọc bằng model hiệu lực như đường thường.
            return try await Self.service(for: VieNeuModelChoice.current).synthesizeWithDuration(
                text: text, voice: voice, speed: speed, boundaryKind: boundaryKind,
                priority: priority, requestID: requestID, synthesisKey: synthesisKey
            )
        }
        let decision = VieNeuHybridRouting.decide(text: text, context: context)
        noteModel(decision, context: context)

        let output: (data: Data, pcmDuration: Double, queueWaitMs: Double, synthesisMs: Double)
        switch decision.model {
        case .nano:
            guard let nano = VieNeuTTSService.shared else { throw HybridError.engineUnavailable("Nano") }
            // Giọng Turbo + máy nóng: Nano nạp lười lần đầu (kèm chạy nháp Core ML), các lần sau đã sẵn.
            if !nano.isPrepared { try await nano.prepare(voice: context.pair.nanoVoice) }
            output = try await nano.synthesizeWithDuration(
                text: text, voice: context.pair.nanoVoice, speed: speed, boundaryKind: boundaryKind,
                priority: priority, requestID: requestID, synthesisKey: synthesisKey
            )
        case .turbo:
            guard let turbo = VieNeuTurboTTSService.shared else { throw HybridError.engineUnavailable("Turbo") }
            output = try await turbo.synthesizeWithDuration(
                text: text, voice: context.pair.turboVoiceId, speed: 1.0, boundaryKind: boundaryKind,
                priority: priority, requestID: requestID, synthesisKey: synthesisKey
            )
        }
        let data = loudness.match(output.data, isBaseModel: decision.model == context.baseModel)
        return (data, output.pcmDuration, output.queueWaitMs, output.synthesisMs)
    }

    // MARK: - Nội bộ

    /// Quên model / mức âm lượng của lượt trước; trả `true` khi phải nhả model phụ (model chính đổi hoặc lần đầu). Hàm đồng
    /// bộ để giữ `lock` ngoài ngữ cảnh `async`.
    private func beginPrepare(baseModel: VieNeuModelChoice?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        lastModel = nil
        let releasesOther = baseModel != nil && preparedBase != baseModel
        preparedBase = baseModel
        loudness.reset()
        return releasesOther
    }

    private static func service(for model: VieNeuModelChoice) throws -> any LocalTTSEngine {
        switch model {
        case .nano:
            guard let nano = VieNeuTTSService.shared else { throw HybridError.engineUnavailable("Nano") }
            return nano
        case .turbo:
            guard let turbo = VieNeuTurboTTSService.shared else { throw HybridError.engineUnavailable("Turbo") }
            return turbo
        }
    }

    /// Một dòng log mỗi lần model của lượt tổng hợp đổi (thứ tự tổng hợp — đoạn nạp trước có thể đi trước đoạn đang phát).
    private func noteModel(_ decision: VieNeuHybridRouting.Decision, context: VieNeuHybridRouting.Context) {
        lock.lock()
        let previous = lastModel
        lastModel = decision.model
        lock.unlock()
        // Lượt đầu sau `prepare` so với model chính: bắt đầu đọc lúc máy đang nóng cũng có một dòng.
        let from = previous ?? context.baseModel
        guard from != decision.model else { return }
        let reason: String
        switch decision.reason {
        case .language:
            reason = "tiếng nước ngoài: " + decision.foreignTokens.prefix(6).joined(separator: ", ")
        case .hot:
            reason = "máy nóng"
        case .base:
            reason = context.baseModel == .turbo ? "máy mát" : "đoạn tiếng Việt"
        }
        AppLogger.shared.log("🔀 [VieNeuHybrid] Đổi model \(from.label) → \(decision.model.label) (lý do: \(reason))")
    }
}
