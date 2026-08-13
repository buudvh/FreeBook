import Foundation

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
        AppLogger.shared.log(String(
            format: "[NghiEnergy] Summary reason=%@ elapsedSec=%.1f synth=%d essential=%d onDemand=%d underrun=%d reusedInFlight=%d avgQueueWaitMs=%.2f aggregateRTF=%.3f maxRTF=%.3f thermal=%@",
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
