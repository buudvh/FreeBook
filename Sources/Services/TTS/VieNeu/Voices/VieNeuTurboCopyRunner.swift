import Foundation
import Observation

/// Nút **"Tạo bản Turbo"** của giọng Nano tự tạo trong chip Turbo của sheet chọn giọng (1.3.900): tải model Turbo + gói
/// nhân bản Turbo nếu thiếu (có %), rồi `VieNeuTurboVoiceCloneCoordinator.createVoice(fromNanoVoiceId:)` trên mẫu Nano đã
/// lưu (khử nhiễu bật như mặc định của sheet nhân bản). Mỗi lúc một giọng.
///
/// Kết quả báo qua `resultMessage` + `resultToken` để View hiện toast (Service không gọi toast).
@MainActor
@Observable
final class VieNeuTurboCopyRunner {
    static let shared = VieNeuTurboCopyRunner()

    enum Phase: Equatable {
        case downloading
        case creating
    }

    /// Id giọng Nano (`VieNeuCustomVoiceStore.Record.id`) đang được tạo bản Turbo.
    private(set) var runningNanoId: String?
    private(set) var phase: Phase?
    private(set) var downloadTargets: [String] = []
    private(set) var downloadTotal: Int64 = 0
    private(set) var resultMessage = ""
    private(set) var resultIsError = false
    private(set) var resultToken = 0

    private init() {}

    var isRunning: Bool { runningNanoId != nil }

    func run(_ voice: VieNeuVoiceDirectory.NanoOnlyVoice) {
        guard runningNanoId == nil else { return }
        guard VieNeuTurboRuntime.isAvailable else {
            report("Bản build này chưa có audio.cpp nên chưa tạo được giọng Turbo.", isError: true)
            return
        }
        guard voice.hasSample else {
            report("Giọng “\(voice.name)” không còn mẫu âm thanh gốc nên chưa tạo được bản Turbo.", isError: true)
            return
        }
        // Kiểm trùng tên trước khi tải gói ~250 MB (kho Turbo không nhận hai giọng cùng tên).
        guard !VieNeuVoiceCloneFlow.contains(VieNeuVoiceDirectory.shared.turboMine, name: voice.name) else {
            report("Đã có giọng Turbo tên “\(voice.name)”. Đổi tên giọng đó trước.", isError: true)
            return
        }
        VieNeuVoicePreviewPlayer.shared.stop()
        runningNanoId = voice.id
        downloadTargets = []
        AppLogger.shared.log("🎙️ [VieNeuClone] Tạo bản Turbo của giọng Nano \(voice.id)")
        Task { [weak self] in
            guard let self else { return }
            do {
                if !VieNeuClonePackages.isReady(nano: false, turbo: true) {
                    phase = .downloading
                    downloadTotal = VieNeuClonePackages.missingBytes(nano: false, turbo: true)
                    try await VieNeuClonePackages.ensure(nano: false, turbo: true) { [weak self] targets in
                        self?.downloadTargets = targets
                    }
                }
                phase = .creating
                try await VieNeuTurboVoiceCloneCoordinator.shared.createVoice(fromNanoVoiceId: voice.id, name: voice.name)
                report("Đã tạo bản Turbo của giọng “\(voice.name)”.", isError: false)
            } catch {
                AppLogger.shared.log("❌ [VieNeuClone] Tạo bản Turbo của \(voice.id) lỗi: \(error.localizedDescription)")
                report("Tạo bản Turbo thất bại: \(error.localizedDescription)", isError: true)
            }
            runningNanoId = nil
            phase = nil
            VieNeuVoiceDirectory.shared.reload()
        }
    }

    private func report(_ message: String, isError: Bool) {
        resultMessage = message
        resultIsError = isError
        resultToken += 1
    }
}
