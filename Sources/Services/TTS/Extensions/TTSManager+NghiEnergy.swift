import Foundation

/// Façade `[NghiEnergy]` — logic nằm ở `NghiEnergyTelemetry` (đợt 8, 1.3.487). Thermal state chỉ được **đọc**
/// để ghi log, không bao giờ điều tiết refill/prefetch (CLAUDE.md).
extension TTSManager {
    internal func recordNghiSynthesis(
        pcmDuration: Double,
        queueWaitMs: Double,
        synthesisMs: Double,
        essential: Bool,
        onDemand: Bool
    ) {
        nghiEnergyTelemetry.recordSynthesis(
            pcmDuration: pcmDuration, queueWaitMs: queueWaitMs, synthesisMs: synthesisMs,
            essential: essential, onDemand: onDemand, thermalState: currentThermalState
        )
    }

    internal func flushNghiEnergySummary(reason: String, force: Bool) {
        nghiEnergyTelemetry.flush(reason: reason, force: force, thermalState: currentThermalState)
    }
}
