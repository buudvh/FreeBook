import Foundation

extension Notification.Name {
    /// Phát khi một lượt tổng hợp engine **local** xong. `Sources/Services/` không được gọi trực tiếp
    /// kiểu ở `Sources/Views/`, nên đây là cầu nối sang `ReaderEnergyDiagnostics` (chỉ để ghi log).
    static let nghiLocalSynthesisDidComplete = Notification.Name("nghiLocalSynthesisDidComplete")
}

extension TTSManager {
    internal func recordNghiSynthesis(
        pcmDuration: Double,
        queueWaitMs: Double,
        synthesisMs: Double,
        essential: Bool,
        onDemand: Bool
    ) {
        guard AppLogger.shared.isLoggingEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if nghiEnergy.startedAt == nil {
            nghiEnergy.startedAt = now
        }
        nghiEnergy.synthesisCount += 1
        if essential { nghiEnergy.essentialCount += 1 }
        if onDemand { nghiEnergy.onDemandCount += 1 }
        nghiEnergy.totalQueueWaitMs += queueWaitMs
        nghiEnergy.totalSynthesisMs += synthesisMs
        nghiEnergy.totalPCMSeconds += pcmDuration
        if pcmDuration > 0 {
            nghiEnergy.maxRTF = max(nghiEnergy.maxRTF, (synthesisMs / 1_000) / pcmDuration)
        }
        // Bắc cầu sang tầng chẩn đoán render: `[NghiEnergy]` và `[ReaderEnergy]` là hai luồng log khác
        // nhau, muốn đối chiếu "nóng ở tầng nào" phải ghép dòng bằng tay. Phát mốc để `[ReaderEnergy]`
        // in thêm `lastLocalSynthAgoMs=` — đọc một dòng là biết tổng hợp vừa chạy hay đã im lâu.
        NotificationCenter.default.post(name: .nghiLocalSynthesisDidComplete, object: nil)
        flushNghiEnergySummary(reason: "interval", force: false)
    }

    internal func flushNghiEnergySummary(reason: String, force: Bool) {
        guard AppLogger.shared.isLoggingEnabled else {
            if force { nghiEnergy = NghiEnergyAccumulator() }
            return
        }
        guard let startedAt = nghiEnergy.startedAt else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = max(0, now - startedAt)
        guard force || elapsed >= 60 else { return }
        guard nghiEnergy.synthesisCount > 0 || nghiEnergy.underrunCount > 0 else {
            nghiEnergy = NghiEnergyAccumulator()
            return
        }

        let averageQueueWaitMs = nghiEnergy.synthesisCount > 0
            ? nghiEnergy.totalQueueWaitMs / Double(nghiEnergy.synthesisCount)
            : 0
        let aggregateRTF = nghiEnergy.totalPCMSeconds > 0
            ? (nghiEnergy.totalSynthesisMs / 1_000) / nghiEnergy.totalPCMSeconds
            : 0
        // Tỉ lệ thời gian CPU bị tổng hợp chiếm trong cả cửa sổ. Đây là trường **phân định tầng nhiệt**:
        // cao (≥85%) ⇒ CPU bận vì chính việc tổng hợp (đòn bẩy là tầng ONNX); thấp mà máy vẫn nóng ⇒
        // thủ phạm ở tầng render. Nếu không đo, hai tầng này nhìn giống nhau qua `aggregateRTF`.
        let busyPct = elapsed > 0 ? (nghiEnergy.totalSynthesisMs / (elapsed * 1_000)) * 100 : 0
        AppLogger.shared.log(String(
            format: "[NghiEnergy] Summary reason=%@ elapsedSec=%.1f synth=%d essential=%d onDemand=%d underrun=%d reusedInFlight=%d avgQueueWaitMs=%.2f aggregateRTF=%.3f maxRTF=%.3f busyPct=%.1f preloadGapMs=%.1f thermal=%@",
            reason,
            elapsed,
            nghiEnergy.synthesisCount,
            nghiEnergy.essentialCount,
            nghiEnergy.onDemandCount,
            nghiEnergy.underrunCount,
            nghiEnergy.reusedInFlightCount,
            averageQueueWaitMs,
            aggregateRTF,
            nghiEnergy.maxRTF,
            busyPct,
            nghiEnergy.maxPreloadGapMs,
            Self.nghiThermalStateName(currentThermalState)
        ))
        nghiEnergy = NghiEnergyAccumulator()
    }

    internal static func nghiThermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
