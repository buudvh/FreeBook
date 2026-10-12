import Foundation
import UIKit

/// Bộ ghi nhiệt nền cho màn "Theo dõi nhiệt" (Cài đặt → Nhà Phát Triển).
///
/// iOS không cho đọc nhiệt độ °C — chỉ `ProcessInfo.thermalState` (4 mức). Kèm theo đó mỗi mẫu ghi % CPU của
/// **riêng app** (CPU-time của tiến trình / thời gian tường; 100% = 1 lõi), pin, đang sạc, Chế độ nguồn điện
/// thấp và engine TTS nếu đang phát — đủ để phân biệt máy nóng do app hay do sạc.
///
/// Thận trọng hiệu năng (yêu cầu của người dùng):
/// - Bộ đệm vòng **cấp phát sẵn** `capacity` ô, mẫu mới ghi đè mẫu cũ nhất: không cấp phát liên tục,
///   **không ghi đĩa**; tắt app là mất.
/// - Một mẫu mỗi `sampleInterval` giây bằng `DispatchSourceTimer` có `leeway` để iOS gộp lần đánh thức; mỗi
///   lần chỉ đọc vài thuộc tính hệ thống. Thêm một mẫu ngay khi iOS báo đổi mức nhiệt.
/// - Khi app bị iOS tạm dừng (không phát TTS, ở nền) bộ hẹn giờ cũng dừng ⇒ biểu đồ có khoảng trống.
@MainActor
final class DeviceThermalMonitor {
    struct Sample {
        let time: Date
        /// `ProcessInfo.ThermalState.rawValue`: 0 bình thường … 3 rất nóng.
        let thermalLevel: Int8
        /// % CPU của app trong khoảng từ mẫu trước; 100 = 1 lõi bận hết.
        let cpuPercent: Float
        /// 0…100, hoặc −1 khi iOS không trả mức pin.
        let batteryPercent: Float
        let isCharging: Bool
        let isLowPowerMode: Bool
        /// Engine TTS (`google`, `vieneu`…) nếu đang phát, `nil` nếu không phát.
        let ttsEngine: String?
    }

    static let shared = DeviceThermalMonitor()

    /// 30 giây/mẫu × 1.440 mẫu = 12 giờ.
    static let sampleInterval: TimeInterval = 30
    static let capacity = 1_440

    private var buffer: ContiguousArray<Sample> = []
    /// Ô sẽ ghi mẫu kế tiếp khi bộ đệm đã đầy.
    private var head = 0
    private var timer: DispatchSourceTimer?
    private var thermalObserver: NSObjectProtocol?
    private var lastCPUMs: Double = 0
    private var lastUptime: TimeInterval = 0

    private init() {
        buffer.reserveCapacity(Self.capacity)
    }

    /// Gọi một lần lúc khởi động app. Gọi lại không có tác dụng.
    func start() {
        guard timer == nil else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        lastCPUMs = ProcessCPUClock.nowMs()
        lastUptime = ProcessInfo.processInfo.systemUptime

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(
            deadline: .now() + Self.sampleInterval,
            repeating: Self.sampleInterval,
            leeway: .seconds(10)
        )
        source.setEventHandler {
            MainActor.assumeIsolated { DeviceThermalMonitor.shared.recordSample() }
        }
        source.resume()
        timer = source

        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { DeviceThermalMonitor.shared.recordSample() }
        }
    }

    /// Các mẫu đang giữ, cũ trước mới sau.
    func samples() -> [Sample] {
        guard buffer.count == Self.capacity else { return Array(buffer) }
        return Array(buffer[head...] + buffer[..<head])
    }

    /// Số liệu tức thời cho phần "Hiện tại" của màn: CPU tính từ mốc `since` do màn tự giữ.
    func liveReading(since baseline: (cpuMs: Double, uptime: TimeInterval)) -> (sample: Sample, baseline: (cpuMs: Double, uptime: TimeInterval)) {
        let cpuMs = ProcessCPUClock.nowMs()
        let uptime = ProcessInfo.processInfo.systemUptime
        let sample = makeSample(cpuMs: cpuMs, uptime: uptime, previousCPUMs: baseline.cpuMs, previousUptime: baseline.uptime)
        return (sample, (cpuMs, uptime))
    }

    private func recordSample() {
        let cpuMs = ProcessCPUClock.nowMs()
        let uptime = ProcessInfo.processInfo.systemUptime
        let sample = makeSample(cpuMs: cpuMs, uptime: uptime, previousCPUMs: lastCPUMs, previousUptime: lastUptime)
        lastCPUMs = cpuMs
        lastUptime = uptime
        if buffer.count < Self.capacity {
            buffer.append(sample)
        } else {
            buffer[head] = sample
            head = (head + 1) % Self.capacity
        }
    }

    private func makeSample(cpuMs: Double, uptime: TimeInterval, previousCPUMs: Double, previousUptime: TimeInterval) -> Sample {
        let wallMs = (uptime - previousUptime) * 1_000
        let cpuPercent = wallMs > 0 ? Float(max(0, cpuMs - previousCPUMs) / wallMs * 100) : 0
        let device = UIDevice.current
        let battery = device.batteryLevel
        let tts = TTSManager.shared
        return Sample(
            time: Date(),
            thermalLevel: Int8(ProcessInfo.processInfo.thermalState.rawValue),
            cpuPercent: cpuPercent,
            batteryPercent: battery < 0 ? -1 : battery * 100,
            isCharging: device.batteryState == .charging || device.batteryState == .full,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            ttsEngine: tts.isPlaying ? tts.tool : nil
        )
    }
}
