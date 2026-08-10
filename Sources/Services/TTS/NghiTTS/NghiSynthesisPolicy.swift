import Foundation

/// Energy policy for the on-device Piper/ONNX pipeline.
///
/// A large audio reserve moves inference earlier but does not reduce the total
/// work. A smaller reserve plus real idle gaps keeps CPU package power from
/// staying continuously elevated during long listening sessions.
enum NghiSynthesisPolicy {
    static func watermarks(for thermalState: ProcessInfo.ThermalState) -> (low: Double, high: Double) {
        switch thermalState {
        case .nominal:
            return (low: 2.5, high: 5.0)
        case .fair:
            return (low: 1.5, high: 3.0)
        case .serious, .critical:
            return (low: 0.0, high: 0.0)
        @unknown default:
            return (low: 1.5, high: 3.0)
        }
    }

    static func allowsSpeculativeRefill(at thermalState: ProcessInfo.ThermalState) -> Bool {
        thermalState == .nominal || thermalState == .fair
    }

    static func allowsNextChapterAudio(at thermalState: ProcessInfo.ThermalState) -> Bool {
        thermalState == .nominal
    }

    static func refillCooldownMilliseconds(
        for thermalState: ProcessInfo.ThermalState,
        configuredDelay: Int
    ) -> Int {
        switch thermalState {
        case .nominal:
            return max(750, configuredDelay)
        case .fair:
            return max(1_500, configuredDelay)
        case .serious, .critical:
            return 0
        @unknown default:
            return max(1_500, configuredDelay)
        }
    }
}
