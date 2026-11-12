import Foundation
import UIKit

/// Kết quả một lượt của "Đo tự động" (`VieNeuAutoThermalRun`). `Codable`: lưu trong tiến độ để Chạy tiếp (1.3.910).
struct VieNeuAutoThermalLeg: Sendable, Codable {
    let index: Int
    let engine: VieNeuAutoThermalRun.Engine
    var skippedReason: String?
    /// Lượt **dở** (bấm Dừng, bị gián đoạn, app bị giết) — Chạy tiếp sẽ chạy lại lượt này.
    var interrupted = false
    /// Chờ mát trước lượt: bao lâu, và có đủ 10 phút `nominal` liền không.
    var settleSeconds: TimeInterval = 0
    var settleNote = ""
    var startCondition = ""
    /// Chế độ tổng hợp lúc bắt đầu → kết thúc lượt (phải là `fast` cả hai — ghim cho cả lượt đo).
    var modeNote = ""
    var secondsToFair: TimeInterval?
    var secondsToSerious: TimeInterval?
    var endReason = ""
    var durationSeconds: TimeInterval = 0
    var chunks = 0
    var audioSeconds = 0.0
    var synthesisSeconds = 0.0
    var processCPUSeconds = 0.0
    var underruns = 0
    var underrunWaitSeconds = 0.0
    var coreML: VieNeuCoreMLFlowBackend.Stats?
    /// Điều kiện máy mỗi phút (nhiệt, mở / khoá màn, sạc, pin, RAM).
    var conditionLines: [String] = []
    /// Nguyên văn báo cáo "Đọc liên tục" của lượt (tổng kết + từng phút + từng đoạn).
    var soakReport = ""

    init(index: Int, engine: VieNeuAutoThermalRun.Engine, skippedReason: String? = nil) {
        self.index = index
        self.engine = engine
        self.skippedReason = skippedReason
    }
}

extension VieNeuAutoThermalRun {
    struct SettleResult: Sendable {
        let seconds: TimeInterval
        let note: String
    }

    // MARK: - Chờ mát

    /// Chờ `nominal` giữ liền `settleHoldSeconds`; quá `settleMaxSeconds` thì chạy luôn và ghi chú.
    func settle(beforeLeg index: Int) async throws -> SettleResult {
        let started = ProcessInfo.processInfo.systemUptime
        var nominalSince: TimeInterval?
        while true {
            try Task.checkCancellation()
            try checkInterruption()
            let now = ProcessInfo.processInfo.systemUptime
            let state = ProcessInfo.processInfo.thermalState
            if state == .nominal {
                nominalSince = nominalSince ?? now
            } else {
                nominalSince = nil
            }
            let held = nominalSince.map { now - $0 } ?? 0
            let waited = now - started
            statusLine = "Chờ máy mát trước lượt \(index + 1)/\(Self.legPlan.count): "
                + "\(VieNeuTurboSoakStats.thermalName(state)) · mát liền \(VieNeuTurboSoakStats.clock(held))"
                + "/\(VieNeuTurboSoakStats.clock(Self.settleHoldSeconds)) · đã chờ \(VieNeuTurboSoakStats.clock(waited))"
            if held >= Self.settleHoldSeconds {
                return SettleResult(seconds: waited, note: "mát liền \(VieNeuTurboSoakStats.clock(held))")
            }
            if waited >= Self.settleMaxSeconds {
                return SettleResult(
                    seconds: waited,
                    note: "⚠️ chờ quá \(VieNeuTurboSoakStats.clock(Self.settleMaxSeconds)) mà chưa đủ mát (\(VieNeuTurboSoakStats.thermalName(state))) — chạy luôn"
                )
            }
            try await Task.sleep(for: .seconds(5))
        }
    }

    // MARK: - Một lượt đọc

    func runLeg(
        index: Int,
        engine: Engine,
        settle: SettleResult,
        lab: VieNeuTurboLab,
        service: VieNeuTTSService,
        voice: String
    ) async throws -> VieNeuAutoThermalLeg {
        var leg = VieNeuAutoThermalLeg(index: index, engine: engine)
        leg.settleSeconds = settle.seconds
        leg.settleNote = settle.note
        leg.startCondition = Self.conditionLine()
        leg.modeNote = "chế độ \(service.currentMode.rawValue)"
        let processed = TTSReplacementManager.shared.applyReplacements(to: VieNeuTurboSampleText.long)
        let chunks = VieNeuTurboSoakRunner.chunks(from: processed)
        let flow: VieNeuFlowBackend? = engine == .coreML ? (backend as VieNeuFlowBackend?) : nil
        backend?.resetStats()
        let speed = Self.synthesisSpeed
        let synthesize: VieNeuTurboSoakRunner.Synthesizer = { text, boundaryKind in
            try await VieNeuTurboLab.nanoChunk(
                service: service, text: text, boundaryKind: boundaryKind, voice: voice, speed: speed, flowBackend: flow
            )
        }
        stopKeepAlive()
        lab.soak.start(
            chunks: chunks,
            engineDescription: "Lượt \(index + 1)/\(Self.legPlan.count) · \(engine.title) · giọng \(voice) · "
                + "tổng hợp \(speed) · phát \(Self.playbackRate)×",
            priority: lab.nanoQoS.priority,
            playbackRate: Self.playbackRate,
            synthesize: synthesize
        )
        AppLogger.shared.log("🎙️ [VieNeuAutoRun] Bắt đầu lượt \(index + 1): \(engine.title) — \(leg.startCondition)")

        let started = ProcessInfo.processInfo.systemUptime
        var seriousAtChunk: Int?
        var nextConditionAt = started + 60
        currentLeg = leg
        defer {
            currentLeg = nil
            startKeepAlive()
        }
        while true {
            do {
                try await Task.sleep(for: .seconds(1))
                try checkInterruption()
            } catch {
                // Giữ phần đã đo của lượt dở (lượt Core ML là lượt quan trọng nhất) rồi mới dừng cả lượt đo.
                leg.endReason = error is CancellationError ? "bấm Dừng" : "dừng: \(error.localizedDescription)"
                leg.interrupted = true
                finishLeg(&leg, lab: lab, service: service, started: started)
                legs.append(leg)
                throw error
            }
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = now - started
            let state = ProcessInfo.processInfo.thermalState
            if state.rawValue >= ProcessInfo.ThermalState.fair.rawValue, leg.secondsToFair == nil {
                leg.secondsToFair = elapsed
            }
            if state.rawValue >= ProcessInfo.ThermalState.serious.rawValue, leg.secondsToSerious == nil {
                leg.secondsToSerious = elapsed
                seriousAtChunk = lab.soak.stats.chunks
            }
            if now >= nextConditionAt {
                leg.conditionLines.append("\(VieNeuTurboSoakStats.clock(elapsed)) · \(Self.conditionLine())")
                nextConditionAt += 60
                snapshotLeg(leg, lab: lab, started: started)
                saveReport()
                progress?.inProgressLeg = currentLeg
                saveProgress()
                trail("lượt \(index + 1) phút \(Int(elapsed / 60)): \(lab.soak.stats.chunks) đoạn")
            }
            if !lab.soak.isRunning {
                leg.endReason = lab.soak.errorMessage.map { "lỗi: \($0)" } ?? lab.soak.statusLine
                break
            }
            if state == .critical {
                leg.endReason = "lên rất nóng (critical)"
                break
            }
            if let seriousAtChunk, lab.soak.stats.chunks >= seriousAtChunk + Self.chunksAfterSerious {
                leg.endReason = "lên nóng rồi đọc thêm \(Self.chunksAfterSerious) đoạn"
                break
            }
            if elapsed >= Self.legMaxSeconds {
                leg.endReason = "hết \(VieNeuTurboSoakStats.clock(Self.legMaxSeconds)) chưa lên nóng"
                break
            }
            statusLine = "Lượt \(index + 1)/\(Self.legPlan.count) (\(engine.title)) · \(VieNeuTurboSoakStats.clock(elapsed))"
                + " · \(VieNeuTurboSoakStats.thermalName(state)) · \(lab.soak.stats.chunks) đoạn"
        }
        finishLeg(&leg, lab: lab, service: service, started: started)
        AppLogger.shared.log("🎙️ [VieNeuAutoRun] Xong lượt \(index + 1): \(leg.endReason)")
        return leg
    }

    /// Chốt số đo của lượt: CPU tiến trình đo **trước** khi dừng trình phát, rồi dừng lượt đọc và chép báo cáo của nó.
    private func finishLeg(
        _ leg: inout VieNeuAutoThermalLeg,
        lab: VieNeuTurboLab,
        service: VieNeuTTSService,
        started: TimeInterval
    ) {
        leg.durationSeconds = ProcessInfo.processInfo.systemUptime - started
        leg.processCPUSeconds = (ProcessCPUClock.nowMs() - lab.soak.stats.startedCPUMs) / 1_000
        lab.soak.stop(reason: leg.endReason)
        fillStats(&leg, lab: lab)
        leg.modeNote += " → \(service.currentMode.rawValue)"
        leg.soakReport = lab.soak.reportText()
    }

    /// Bản chụp giữa lượt cho báo cáo (không dừng gì).
    private func snapshotLeg(_ leg: VieNeuAutoThermalLeg, lab: VieNeuTurboLab, started: TimeInterval) {
        var partial = leg
        partial.durationSeconds = ProcessInfo.processInfo.systemUptime - started
        partial.processCPUSeconds = (ProcessCPUClock.nowMs() - lab.soak.stats.startedCPUMs) / 1_000
        partial.endReason = "(đang chạy)"
        fillStats(&partial, lab: lab)
        currentLeg = partial
    }

    private func fillStats(_ leg: inout VieNeuAutoThermalLeg, lab: VieNeuTurboLab) {
        let stats = lab.soak.stats
        leg.chunks = stats.chunks
        leg.audioSeconds = stats.audioSeconds
        leg.synthesisSeconds = stats.synthesisMs / 1_000
        leg.underruns = stats.underruns
        leg.underrunWaitSeconds = stats.underrunWaitMs / 1_000
        leg.coreML = leg.engine == .coreML ? backend?.statsSnapshot : nil
    }

    // MARK: - Điều kiện máy / gián đoạn

    /// TTS / nhạc / phim khác đang phát ⇒ dừng cả lượt đo (số đo nhiệt không còn của riêng engine đang thử).
    func checkInterruption() throws {
        if TTSManager.shared.isPlaying || AudioPlaybackFlag.isPlaying || VideoNativePlaybackFlag.isPlaying {
            throw RunError.message("Bị gián đoạn: TTS / nhạc / phim khác đang phát — dừng lượt đo để không ra số sai.")
        }
    }

    /// App đang mở màn hay chạy nền / khoá màn — Core ML có thể không nạp được khi app ở nền (lần đo 1.3.907).
    static func appStateName() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return "đang mở màn"
        case .inactive: return "chuyển cảnh"
        case .background: return "nền / khoá màn"
        @unknown default: return "?"
        }
    }

    /// "nominal (mát) · khoá màn · rút sạc 78% · RAM 512 MB · trống 1.400 MB".
    static func conditionLine() -> String {
        let app = appStateName()
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let battery: String
        switch device.batteryState {
        case .charging: battery = "đang sạc"
        case .full: battery = "cắm sạc (đầy)"
        case .unplugged: battery = "rút sạc"
        case .unknown: battery = "pin ?"
        @unknown default: battery = "pin ?"
        }
        let level = device.batteryLevel >= 0 ? " \(Int((device.batteryLevel * 100).rounded()))%" : ""
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled ? " · Chế độ nguồn điện thấp" : ""
        return "\(VieNeuTurboSoakStats.thermalName(ProcessInfo.processInfo.thermalState)) · \(app) · \(battery)\(level)"
            + "\(lowPower) · \(ProcessMemoryProbe.snapshot().summary)"
    }
}
