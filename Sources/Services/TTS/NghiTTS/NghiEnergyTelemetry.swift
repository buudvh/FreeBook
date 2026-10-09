import Foundation

extension Notification.Name {
    /// Phát khi một lượt tổng hợp engine **local** xong. `Sources/Services/` không được gọi trực tiếp
    /// kiểu ở `Sources/Views/`, nên đây là cầu nối sang `ReaderEnergyDiagnostics` (chỉ để ghi log).
    static let nghiLocalSynthesisDidComplete = Notification.Name("nghiLocalSynthesisDidComplete")
}

/// Bộ đếm năng lượng của engine local (`[NghiEnergy]`) — tách khỏi `TTSManager` (đợt 8 tách god object, 1.3.487).
///
/// **Chỉ ghi log, không bao giờ điều tiết**: thermal state là telemetry (CLAUDE.md), nhận từ caller lúc gọi.
/// Mọi hàm giữ nguyên cửa `AppLogger.shared.isLoggingEnabled` như cũ, trừ `markPlaybackSubmitted()` —
/// cố ý **không** gate để `maxPreloadGapMs` đo đúng kể cả khi người dùng bật log giữa chừng (y hệt hai
/// phép gán `nghiEnergy.lastPlaybackSubmitAt = …` cũ trong `playNghiTTS`). Cửa sổ tổng kết 60 s giữ nguyên.
@MainActor
final class NghiEnergyTelemetry {
    struct Accumulator {
        var startedAt: TimeInterval?
        var synthesisCount = 0
        var essentialCount = 0
        var onDemandCount = 0
        var underrunCount = 0
        var reusedInFlightCount = 0
        var totalQueueWaitMs = 0.0
        var totalSynthesisMs = 0.0
        var totalPCMSeconds = 0.0
        var maxRTF = 0.0
        /// Chặng chờ **giữa hai đoạn liền kề** (đoạn cũ phát xong → đoạn mới sẵn sàng), đơn vị ms.
        /// Khác `avgQueueWaitMs` (chờ *trong* coordinator): đây là chờ ở tầng phát, đúng thứ người dùng
        /// nghe ra. Chỉ cập nhật ở `recordUnderrun` nên không thêm phép đo trên hot path.
        var maxPreloadGapMs = 0.0
        /// Mốc `uptime` lần cuối một đoạn được đưa lên hàng đợi phát. Dùng để tính `maxPreloadGapMs`:
        /// hụt xảy ra ⇒ khoảng từ mốc này tới lúc hụt chính là chặng chờ người dùng nghe ra.
        var lastPlaybackSubmitAt: TimeInterval?
    }

    private var nghiEnergy = Accumulator()

    func recordSynthesis(
        pcmDuration: Double,
        queueWaitMs: Double,
        synthesisMs: Double,
        essential: Bool,
        onDemand: Bool,
        thermalState: ProcessInfo.ThermalState
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
        flush(reason: "interval", force: false, thermalState: thermalState)
    }

    func recordUnderrun(index: Int, reusedInFlight: Bool, chapterIndex: Int, thermalState: ProcessInfo.ThermalState) {
        guard AppLogger.shared.isLoggingEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if nghiEnergy.startedAt == nil {
            nghiEnergy.startedAt = now
        }
        nghiEnergy.underrunCount += 1
        if reusedInFlight {
            nghiEnergy.reusedInFlightCount += 1
        }
        // Chặng chờ thật: từ lúc đoạn trước được đưa lên hàng đợi phát tới lúc hụt đoạn này.
        if let submittedAt = nghiEnergy.lastPlaybackSubmitAt {
            nghiEnergy.maxPreloadGapMs = max(nghiEnergy.maxPreloadGapMs, (now - submittedAt) * 1_000)
        }
        AppLogger.shared.log(
            "[NghiEnergy] Underrun chapter=\(chapterIndex) index=\(index) reusedInFlight=\(reusedInFlight) thermal=\(Self.thermalStateName(thermalState))"
        )
        flush(reason: "interval", force: false, thermalState: thermalState)
    }

    /// Không gate theo `isLoggingEnabled` — xem doc đầu file.
    func markPlaybackSubmitted() {
        nghiEnergy.lastPlaybackSubmitAt = ProcessInfo.processInfo.systemUptime
    }

    func flush(reason: String, force: Bool, thermalState: ProcessInfo.ThermalState) {
        guard AppLogger.shared.isLoggingEnabled else {
            if force { nghiEnergy = Accumulator() }
            return
        }
        guard let startedAt = nghiEnergy.startedAt else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = max(0, now - startedAt)
        guard force || elapsed >= 60 else { return }
        guard nghiEnergy.synthesisCount > 0 || nghiEnergy.underrunCount > 0 else {
            nghiEnergy = Accumulator()
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
            Self.thermalStateName(thermalState)
        ))
        nghiEnergy = Accumulator()
    }

    nonisolated static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
