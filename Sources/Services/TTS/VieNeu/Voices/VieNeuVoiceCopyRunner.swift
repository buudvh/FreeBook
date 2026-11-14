import Foundation
import Observation

/// **Nhân bản chéo Nano ↔ Turbo** (1.3.937, thay `VieNeuTurboCopyRunner` của 1.3.901): "Tạo bản Turbo" cho giọng Nano,
/// "Tạo bản Nano" cho giọng Turbo — giọng có sẵn lẫn giọng tự tạo. Mỗi lúc một lượt.
///
/// 1. Tải gói của model đích nếu thiếu (`VieNeuClonePackages`, có %).
/// 2. Mẫu: có mẫu gốc thì dùng (`VieNeuVoiceCopySource.sampleURL`); không có thì cho chính giọng đó đọc đoạn mẫu ~15 s
///    (`VieNeuVoiceSampleSpeaker`) — chặn khi truyện **đang phát** (dùng chung engine với trình đọc).
/// 3. Tạo: Turbo qua `VieNeuTurboVoiceCloneCoordinator` (giọng Nano tự tạo còn mẫu ⇒ `createVoice(fromNanoVoiceId:)` như cũ),
///    Nano qua `VieNeuNanoVoiceCreator`. Bản mới cùng tên giọng nguồn và mang liên kết cặp (`sourceNanoVoiceId` /
///    `sourceNanoPresetName` / `sourceTurboVoiceId`) ⇒ `VieNeuVoicePairing` nhận ngay (bỏ đệm 30 s).
///
/// Kết quả báo bằng toast qua `TTSPresentationEventCenter` (Service không gọi toast) + log `🎙️ [VieNeuCopy]`;
/// `completionToken` / `lastOutcome` cho lối tự tạo của đọc lai (`VieNeuHybridPairProvisioner`).
@MainActor
@Observable
final class VieNeuVoiceCopyRunner {
    static let shared = VieNeuVoiceCopyRunner()

    enum Phase: Equatable {
        case downloading
        case speaking
        case creating
    }

    struct Outcome: Equatable {
        let sourceKey: String
        let succeeded: Bool
        let message: String
    }

    private(set) var job: VieNeuVoiceCopySource?
    private(set) var phase: Phase?
    private(set) var nanoStage: VieNeuVoiceCloner.Stage?
    private(set) var downloadTargets: [String] = []
    private(set) var downloadTotal: Int64 = 0
    private(set) var lastOutcome: Outcome?
    private(set) var completionToken = 0

    private init() {}

    var isRunning: Bool { job != nil }

    func isRunning(_ source: VieNeuVoiceCopySource) -> Bool {
        job?.id == source.id
    }

    /// Vì sao chưa tạo được; `nil` = được.
    func blockReason(for source: VieNeuVoiceCopySource) -> String? {
        if isRunning { return "Đang tạo một bản giọng khác — chờ lượt đó xong." }
        if (source.model == .turbo || source.target == .turbo), !VieNeuTurboRuntime.isAvailable {
            return "Bản build này chưa có audio.cpp nên chưa tạo được bản Turbo."
        }
        if !source.hasSample, TTSManager.shared.isPlaying {
            return "Đang phát truyện. Dừng phát rồi tạo bản \(source.target.label)."
        }
        let directory = VieNeuVoiceDirectory.shared
        let taken = source.target == .nano
            ? directory.nanoMine + directory.nanoPresets
            : directory.turboMine
        if VieNeuVoiceCloneFlow.contains(taken, name: source.name) {
            return "Đã có giọng \(source.target.label) tên “\(source.name)”. Đổi tên giọng đó trước."
        }
        return nil
    }

    /// Bắt đầu một lượt. Trả lý do khi không chạy được (bên gọi tự báo); `nil` = đã bắt đầu.
    @discardableResult
    func run(_ source: VieNeuVoiceCopySource, automatic: Bool = false) -> String? {
        if let reason = blockReason(for: source) { return reason }
        VieNeuVoicePreviewPlayer.shared.stop()
        job = source
        phase = nil
        nanoStage = nil
        downloadTargets = []
        downloadTotal = 0
        AppLogger.shared.log(
            "🎙️ [VieNeuCopy] Tạo bản \(source.target.label) của \(source.id) (\(source.hasSample ? "từ mẫu gốc" : "từ tiếng máy đọc")\(automatic ? ", tự tạo cho đọc lai" : ""))"
        )
        Task { [weak self] in await self?.execute(source) }
        return nil
    }

    // MARK: - Nội bộ

    private func execute(_ source: VieNeuVoiceCopySource) async {
        var spokenURL: URL?
        let message: String
        var succeeded = false
        do {
            let wantsNano = source.target == .nano
            if !VieNeuClonePackages.isReady(nano: wantsNano, turbo: !wantsNano) {
                phase = .downloading
                downloadTotal = VieNeuClonePackages.missingBytes(nano: wantsNano, turbo: !wantsNano)
                try await VieNeuClonePackages.ensure(nano: wantsNano, turbo: !wantsNano) { [weak self] jobs in
                    self?.downloadTargets = jobs.all
                }
            }
            var sampleURL = source.sampleURL
            if sampleURL == nil {
                phase = .speaking
                spokenURL = try await VieNeuVoiceSampleSpeaker.speak(source.selection)
                sampleURL = spokenURL
            }
            guard let sampleURL else { throw VieNeuVoiceSampleSpeaker.SpeakError.empty }
            phase = .creating
            let detail = try await create(source, sampleURL: sampleURL, isSpoken: spokenURL != nil)
            VieNeuVoicePairing.shared.invalidate()
            message = "Đã tạo bản \(source.target.label) của “\(source.name)”\(detail)."
            succeeded = true
        } catch {
            message = "Tạo bản \(source.target.label) của “\(source.name)” lỗi: \(error.localizedDescription)"
            AppLogger.shared.log("❌ [VieNeuCopy] \(message)")
        }
        if let spokenURL { try? FileManager.default.removeItem(at: spokenURL) }
        // Đọc mẫu bằng model khác model trình đọc ⇒ nạp lại engine trình đọc (như thử giọng, `finishSession`).
        let tts = TTSManager.shared
        if spokenURL != nil, tts.tool == "vieneu", source.model != VieNeuModelChoice.current {
            tts.scheduleNghiWarmUp()
        }
        if succeeded {
            AppLogger.shared.log("🎙️ [VieNeuCopy] \(message)")
        }
        TTSPresentationEventCenter.shared.send(.showToast(message: message, type: succeeded ? .success : .error))
        job = nil
        phase = nil
        nanoStage = nil
        lastOutcome = Outcome(sourceKey: source.id, succeeded: succeeded, message: message)
        completionToken += 1
        VieNeuVoiceDirectory.shared.reload()
    }

    /// Tạo bản ở model đích; trả phần ghi chú thêm cho câu báo ("" khi không có gì).
    private func create(_ source: VieNeuVoiceCopySource, sampleURL: URL, isSpoken: Bool) async throws -> String {
        let spokenNote = isSpoken ? " từ tiếng máy đọc" : ""
        switch source.target {
        case .turbo:
            let coordinator = VieNeuTurboVoiceCloneCoordinator.shared
            let outcome: VieNeuTurboVoiceCloneCoordinator.Outcome
            if let nanoId = source.nanoRecordId, !isSpoken {
                outcome = try await coordinator.createVoice(fromNanoVoiceId: nanoId, name: source.name)
            } else {
                // Tiếng máy đọc sạch ⇒ không khử nhiễu (chỉ cần `speaker_encoder`).
                outcome = try await coordinator.createVoice(
                    fromFile: sampleURL,
                    name: source.name,
                    denoise: !isSpoken,
                    keepsSample: false,
                    sourceNanoVoiceId: source.nanoRecordId,
                    sourceNanoPresetName: source.isCustom ? nil : source.selection.voiceId
                )
            }
            let prepared = outcome.prepared
            guard prepared.speechSeconds > VieNeuTurboReferencePreparer.cutSeconds else { return spokenNote }
            return spokenNote + String(format: ", dùng %.1f s đầu của mẫu", prepared.durationSeconds)
                .replacingOccurrences(of: ".", with: ",")
        case .nano:
            try await VieNeuNanoVoiceCreator.create(
                name: source.name,
                sampleURL: sampleURL,
                sourceTurboVoiceId: source.selection.voiceId
            ) { stage in
                Task { @MainActor in VieNeuVoiceCopyRunner.shared.nanoStage = stage }
            }
            return spokenNote
        }
    }
}
