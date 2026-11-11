import Foundation

/// Bộ đếm của chế độ "Đọc liên tục (đo nhiệt)": tổng cả lượt + cửa sổ từng phút.
///
/// **CPU/tiếng** = CPU-time **cả tiến trình** (`ProcessCPUClock`, gồm mọi luồng của ggml / ORT và cả trình phát) chia cho
/// số giây tiếng **đã tổng hợp** trong cùng khoảng — đúng cách `NghiEnergyTelemetry` tính `cpuPerAudioSec`. Nhiệt tỉ lệ
/// với CPU-time chứ không với thời gian tường, nên đây là con số đáng so giữa Turbo và Nano. Khi bộ sinh chạy kịp, số
/// giây đã tổng hợp ≈ số giây đã phát (bộ sinh chỉ đi trước tối đa 2 đoạn).
struct VieNeuTurboSoakStats {
    struct Window {
        var startedAt: TimeInterval
        var startedCPUMs: Double
        var chunks = 0
        var audioSeconds = 0.0
        var synthesisMs = 0.0
        var underruns = 0
    }

    private(set) var startedAt: TimeInterval
    private(set) var startedCPUMs: Double
    private(set) var chunks = 0
    private(set) var characters = 0
    private(set) var audioSeconds = 0.0
    private(set) var synthesisMs = 0.0
    /// Tổng CPU-time đo **quanh từng lượt tổng hợp** (không gồm lúc chỉ phát) — để tách phần của engine.
    private(set) var synthesisCPUMs = 0.0
    private(set) var underruns = 0
    private(set) var underrunWaitMs = 0.0
    private(set) var minuteIndex = 0
    private(set) var window: Window

    init(now: TimeInterval = ProcessInfo.processInfo.systemUptime, cpuMs: Double = ProcessCPUClock.nowMs()) {
        startedAt = now
        startedCPUMs = cpuMs
        window = Window(startedAt: now, startedCPUMs: cpuMs)
    }

    mutating func recordChunk(characters: Int, audioSeconds: Double, synthesisMs: Double, cpuMs: Double) {
        chunks += 1
        self.characters += characters
        self.audioSeconds += audioSeconds
        self.synthesisMs += synthesisMs
        synthesisCPUMs += cpuMs
        window.chunks += 1
        window.audioSeconds += audioSeconds
        window.synthesisMs += synthesisMs
    }

    /// Trình phát hết đoạn mà đoạn kế chưa xong — gọi lúc **bắt đầu** chờ.
    mutating func recordUnderrunStart() {
        underruns += 1
        window.underruns += 1
    }

    /// Đoạn kế đã tới — cộng thời gian người nghe phải chờ.
    mutating func recordUnderrunEnd(waitMs: Double) {
        underrunWaitMs += waitMs
    }

    /// Đóng cửa sổ hiện tại, trả dòng tổng kết của phút vừa qua, rồi mở cửa sổ mới.
    mutating func closeMinute(
        now: TimeInterval = ProcessInfo.processInfo.systemUptime,
        cpuMs: Double = ProcessCPUClock.nowMs(),
        thermal: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> String {
        minuteIndex += 1
        let cpuSeconds = (cpuMs - window.startedCPUMs) / 1_000
        let wallSeconds = max(0.001, now - window.startedAt)
        let line = String(
            format: "Phút %d · %d đoạn · tiếng %.1f s · CPU %.1f s (%.0f%% một lõi) · CPU/tiếng %@ · hụt %d · %@",
            minuteIndex,
            window.chunks,
            window.audioSeconds,
            cpuSeconds,
            cpuSeconds / wallSeconds * 100,
            Self.ratio(cpuSeconds, window.audioSeconds),
            window.underruns,
            Self.thermalName(thermal)
        )
        window = Window(startedAt: now, startedCPUMs: cpuMs)
        return line
    }

    /// Tổng kết cả lượt từ lúc bấm bắt đầu.
    func summary(
        now: TimeInterval = ProcessInfo.processInfo.systemUptime,
        cpuMs: Double = ProcessCPUClock.nowMs(),
        thermal: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> String {
        let wallSeconds = max(0.001, now - startedAt)
        let cpuSeconds = (cpuMs - startedCPUMs) / 1_000
        let synthesisSeconds = synthesisMs / 1_000
        return """
        thời gian     \(Self.clock(wallSeconds))
        đoạn          \(chunks) (\(characters) ký tự)
        tiếng         \(String(format: "%.1f", audioSeconds)) s
        CPU tiến trình \(String(format: "%.1f", cpuSeconds)) s (\(String(format: "%.0f", cpuSeconds / wallSeconds * 100))% một lõi)
        CPU/tiếng     \(Self.ratio(cpuSeconds, audioSeconds))   (CPU-s mỗi giây tiếng, cả tiến trình)
        CPU tổng hợp  \(Self.ratio(synthesisCPUMs / 1_000, audioSeconds))   (chỉ trong lúc tổng hợp)
        RTF           \(Self.ratio(synthesisSeconds, audioSeconds))   (tổng hợp / tiếng)
        hụt tiếng     \(underruns) lần, chờ \(String(format: "%.1f", underrunWaitMs / 1_000)) s
        nhiệt         \(Self.thermalName(thermal))
        """
    }

    static func ratio(_ numerator: Double, _ denominator: Double) -> String {
        guard denominator > 0.001 else { return "—" }
        return String(format: "%.2f", numerator / denominator)
    }

    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Nhãn trạng thái nhiệt: tên của Apple (để khớp log của engine khác) + nghĩa tiếng Việt.
    static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal (mát)"
        case .fair: return "fair (ấm)"
        case .serious: return "serious (nóng)"
        case .critical: return "critical (rất nóng)"
        @unknown default: return "unknown"
        }
    }
}
