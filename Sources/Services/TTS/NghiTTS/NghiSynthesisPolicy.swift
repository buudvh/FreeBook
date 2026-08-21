import Foundation

/// Energy policy for the on-device Piper/ONNX pipeline.
///
/// A large audio reserve moves inference earlier but does not reduce the total
/// work. A smaller reserve plus real idle gaps keeps CPU package power from
/// staying continuously elevated during long listening sessions.
enum NghiSynthesisPolicy {
    static let defaultSafeCachedTimeThreshold: Double = 8.0
    static let safeCachedTimeThresholdRange: ClosedRange<Double> = 4.0...20.0
    static let maxOptionalReserveItems: Int = 2

    /// Trần tổng số payload audio logic giữ đồng thời cho NghiTTS: đoạn hiện tại + `N+1`
    /// + tối đa 2 optional reserve + chunk 0 chương kế. Prefix chương kế **mượn** trong
    /// đúng trần này chứ không nới nó ra.
    static let maxTotalAudioPayloads: Int = 5

    static func clampSafeCachedTimeThreshold(_ value: Double) -> Double {
        max(safeCachedTimeThresholdRange.lowerBound, min(safeCachedTimeThresholdRange.upperBound, value))
    }

    static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
