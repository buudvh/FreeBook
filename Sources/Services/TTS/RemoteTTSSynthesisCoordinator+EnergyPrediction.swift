import Foundation

/// Dự đoán mức tải của dòng `[TTSEnergy] Summary` — hàm thuần, tách khỏi `RemoteTTSSynthesisCoordinator.swift` để file
/// gốc ở dưới trần dòng (1.3.960).
extension RemoteTTSSynthesisCoordinator {
    internal static func energyPrediction(
        applicationState: String,
        requestsPerMinute: Double,
        busyPercent: Double,
        thermalState: ProcessInfo.ThermalState
    ) -> String {
        if thermalState == .serious || thermalState == .critical {
            return "thermal_pressure_confirmed"
        }
        if applicationState == "background" && (requestsPerMinute >= 15 || busyPercent >= 50) {
            return "background_remote_load_likely"
        }
        if requestsPerMinute >= 18 || busyPercent >= 60 {
            return "sustained_remote_load_likely"
        }
        if requestsPerMinute >= 10 || busyPercent >= 30 {
            return "remote_load_elevated"
        }
        return "remote_load_low"
    }
}
