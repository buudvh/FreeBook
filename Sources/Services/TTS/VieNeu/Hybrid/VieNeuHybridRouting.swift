import Foundation

/// **Đọc lai Nano · Turbo** (1.3.934) — quyết model cho từng lượt tổng hợp của trình đọc VieNeu. Báo cáo
/// `Docs/Reports/2026-11-14-vieneu-nano-turbo-theo-ngon-ngu.md` §7.2, §8–9.
///
/// ## Khi nào bật
/// `tool == "vieneu"`, giọng đang dùng có **cặp** (`VieNeuVoicePairing`), cả hai model + file giọng Turbo của cặp có trên máy,
/// và công tắc của model đang chọn bật:
/// - giọng **Nano** ⇒ phương án A (`VieNeuHybridSettings.isLanguageRoutingEnabled`): đoạn tiếng nước ngoài đọc Turbo;
/// - giọng **Turbo** ⇒ phương án B (`isThermalRoutingEnabled`): máy nóng đọc Nano, mát lại về Turbo.
/// A **nhường** B: công tắc B bật và máy đang nóng thì đoạn tiếng nước ngoài vẫn đọc Nano.
///
/// ## Tất định theo chữ
/// `decide(text:context:)` là hàm của chữ đoạn + trạng thái nhiệt (đổi hiếm, có trễ) ⇒ khoá tổng hợp
/// (`synthesisEngineIdentity`) tính lại được ở mọi chỗ (refill, prefetch chương kế, prefix chương kế) mà không lệch model.
///
/// Hàm thuần (`UserDefaults` + kiểm file + đệm có khoá) ⇒ gọi được ngoài `MainActor`.
enum VieNeuHybridRouting {
    struct Context: Hashable, Sendable {
        /// Model của giọng đang chọn — model "chính".
        let baseModel: VieNeuModelChoice
        let pair: VieNeuVoicePairing.Pair
    }

    enum Reason: String, Sendable {
        /// Model chính của giọng.
        case base
        /// Đoạn có tiếng nước ngoài (A).
        case language
        /// Máy nóng (B, hoặc A nhường B).
        case hot
    }

    struct Decision: Sendable {
        let model: VieNeuModelChoice
        let reason: Reason
        let foreignTokens: [String]
    }

    private static let vieNeuTool = "vieneu"
    /// Tần số của Turbo — nhận diện đoạn Turbo trong hàng đợi phát (`playbackRateFactor`).
    private static let turboSampleRate = Double(VieNeuTurboTTSService.sampleRate)

    /// Ngữ cảnh đọc lai cho giọng `voice` của model **hiệu lực** (`VieNeuModelChoice.current`), `nil` = đọc như thường.
    /// Người gọi bảo đảm `tool == "vieneu"`.
    static func context(voice: String) -> Context? {
        let model = VieNeuModelChoice.current
        let applies = model == .nano
            ? VieNeuHybridSettings.isLanguageRoutingEnabled
            : VieNeuHybridSettings.isThermalRoutingEnabled
        guard applies,
              VieNeuTurboTTSService.isReadyOnDisk,
              VieNeuTTSService.shared?.modelStore.isReady == true,
              let pair = VieNeuVoicePairing.shared.pair(model: model, voice: voice),
              VieNeuTurboTTSService.shared?.store.hasVoice(voiceId: pair.turboVoiceId) == true else { return nil }
        return Context(baseModel: model, pair: pair)
    }

    /// Ngữ cảnh của **trình đọc** khi không có `TTSManager` trong tay (luồng nền: hai service quyết có nhả model kia không,
    /// Core ML có chạy nháp không). Giọng lấy từ lựa chọn đã lưu, như `TTSManager.effectiveVieNeuVoice`.
    static func readerContext() -> Context? {
        guard UserDefaults.standard.string(forKey: "ttsTool") == vieNeuTool else { return nil }
        let model = VieNeuModelChoice.current
        let stored = VieNeuVoiceSelection.stored
        let voice = stored.model == model ? stored.voiceId : (VieNeuVoiceSelection.lastNanoVoice ?? "")
        return context(voice: voice)
    }

    static func decide(text: String, context: Context) -> Decision {
        switch context.baseModel {
        case .nano:
            let verdict = VieNeuForeignTextClassifier.shared.verdict(for: text)
            guard verdict.prefersTurbo else {
                return Decision(model: .nano, reason: .base, foreignTokens: [])
            }
            // A nhường B: chỉ khi công tắc "Máy nóng thì đọc bằng Nano" bật — tắt nó là nhiệt không đổi model nữa.
            if VieNeuHybridSettings.isThermalRoutingEnabled, VieNeuThermalGovernor.shared.isHot {
                return Decision(model: .nano, reason: .hot, foreignTokens: verdict.foreignTokens)
            }
            return Decision(model: .turbo, reason: .language, foreignTokens: verdict.foreignTokens)
        case .turbo:
            if VieNeuThermalGovernor.shared.isHot {
                return Decision(model: .nano, reason: .hot, foreignTokens: [])
            }
            return Decision(model: .turbo, reason: .base, foreignTokens: [])
        }
    }

    /// Tên engine trong khoá tổng hợp khi đang đọc lai: `vieneu.hybrid.<model của đoạn>`; `nil` = không đọc lai. Khác hẳn
    /// `vieneu` / `vieneu.turbo` ⇒ bật / tắt đọc lai không bao giờ phát nhầm audio của chế độ kia.
    static func synthesisEngineIdentity(voice: String, text: String) -> String? {
        guard let context = context(voice: voice) else { return nil }
        return "vieneu.hybrid.\(decide(text: text, context: context).model.rawValue)"
    }

    /// Hệ số nhân tốc độ phát cho một đoạn trong hàng đợi (`NghiAudioPlayerQueue`). Giọng **Nano** đọc lai (A): đoạn Turbo
    /// (48 kHz — trình đọc Nano không tự sinh 48 kHz) tổng hợp ở 1× trong khi Nano tổng hợp ở "Tốc độ tổng hợp" ⇒ nhân đoạn
    /// Turbo với đúng tốc độ đó để hai giọng nói cùng nhịp. Giọng Turbo (B): đoạn Nano tổng hợp ở 1× như Turbo ⇒ không nhân.
    static func playbackRateFactor(sampleRate: Double) -> Float {
        guard abs(sampleRate - turboSampleRate) < 1,
              UserDefaults.standard.string(forKey: "ttsTool") == vieNeuTool,
              VieNeuModelChoice.current == .nano else { return 1 }
        return Float(TTSManager.vieNeuSynthesisSpeed)
    }
}
