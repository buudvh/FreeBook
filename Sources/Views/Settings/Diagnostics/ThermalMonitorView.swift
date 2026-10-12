import SwiftUI

/// Màn "Theo dõi nhiệt" (Cài đặt → Nhà Phát Triển).
///
/// - "Hiện tại": đọc trực tiếp mỗi 2 giây khi màn đang mở (CPU tính từ mốc riêng của màn).
/// - Hai biểu đồ: lịch sử từ bộ đệm RAM của `DeviceThermalMonitor` (mẫu 30 giây, giữ 12 giờ), làm mới mỗi 30 giây.
/// - Nút chia sẻ: CSV dựng trong RAM lúc bấm (`ThermalCSVExport`).
struct ThermalMonitorView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var current: DeviceThermalMonitor.Sample?
    @State private var history: [DeviceThermalMonitor.Sample] = []
    @State private var cpuBaselineMs: Double = 0
    @State private var uptimeBaseline: TimeInterval = 0

    private static let liveRefreshNanoseconds: UInt64 = 2_000_000_000
    /// Lịch sử chỉ có mẫu mới mỗi 30 giây ⇒ làm mới sau mỗi 15 nhịp 2 giây.
    private static let historyRefreshTicks = 15

    var body: some View {
        Form {
            Section {
                LabeledContent("Mức nhiệt") {
                    Text(Self.levelName(thermalLevel))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .foregroundColor(Self.levelColor(thermalLevel))
                        .background(Self.levelColor(thermalLevel).opacity(0.15))
                        .clipShape(Capsule())
                }
                LabeledContent("CPU app", value: current.map { String(format: "%.0f%%", $0.cpuPercent) } ?? "—")
                LabeledContent("Pin", value: batteryText)
                LabeledContent("Chế độ nguồn điện thấp", value: (current?.isLowPowerMode ?? ProcessInfo.processInfo.isLowPowerModeEnabled) ? "Bật" : "Tắt")
                LabeledContent("TTS", value: ttsText)
            } header: {
                Text("Hiện tại")
            } footer: {
                Text("Cập nhật mỗi 2 giây. CPU app: 100% = 1 lõi. iOS không cho đọc nhiệt độ °C, chỉ 4 mức.")
            }

            Section {
                ThermalMonitorChart(kind: .level, samples: history)
            } header: {
                Text("Mức nhiệt (12 giờ gần nhất)")
            }

            Section {
                ThermalMonitorChart(kind: .usage, samples: history)
            } header: {
                Text("CPU app và pin")
            } footer: {
                Text("Mẫu mỗi 30 giây từ lúc mở app, giữ 12 giờ trong RAM, tắt app là mất.")
            }
        }
        .navigationTitle("Theo dõi nhiệt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: ThermalCSVExport(), preview: SharePreview("Dữ liệu nhiệt")) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 38)
                }
                .disabled(history.isEmpty)
                .accessibilityLabel("Chia sẻ dữ liệu nhiệt")
            }
        }
        // Chỉ chạy khi app đang hiện: ở nền (vd để mở màn này rồi khoá máy nghe TTS) task bị huỷ, không đánh
        // thức main mỗi 2 giây; trở lại `.active` thì chạy lại và nạp lại lịch sử.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await runLiveUpdates()
        }
    }

    /// Mức nhiệt đang hiện: từ lần đọc gần nhất, hoặc đọc thẳng `ProcessInfo` khi chưa có mẫu nào
    /// (khoảng 30 giây đầu sau khi mở app) — không hiện "Bình thường" giả.
    private var thermalLevel: Int {
        current.map { Int($0.thermalLevel) } ?? ProcessInfo.processInfo.thermalState.rawValue
    }

    private var batteryText: String {
        guard let sample = current, sample.batteryPercent >= 0 else { return "—" }
        let percent = String(format: "%.0f%%", sample.batteryPercent)
        return sample.isCharging ? "\(percent) · Đang sạc" : percent
    }

    private var ttsText: String {
        guard let engine = current?.ttsEngine else { return "Không phát" }
        return "Đang phát · \(TTSSettingsHubView.engineName(for: engine))"
    }

    /// Hiện mẫu gần nhất ngay khi mở màn, rồi đọc trực tiếp mỗi 2 giây; dừng khi rời màn (task bị huỷ).
    private func runLiveUpdates() async {
        let monitor = DeviceThermalMonitor.shared
        history = monitor.samples()
        current = history.last
        cpuBaselineMs = ProcessCPUClock.nowMs()
        uptimeBaseline = ProcessInfo.processInfo.systemUptime
        var tick = 0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.liveRefreshNanoseconds)
            guard !Task.isCancelled else { return }
            let reading = monitor.liveReading(since: (cpuBaselineMs, uptimeBaseline))
            current = reading.sample
            cpuBaselineMs = reading.baseline.cpuMs
            uptimeBaseline = reading.baseline.uptime
            tick += 1
            if tick % Self.historyRefreshTicks == 0 {
                history = monitor.samples()
            }
        }
    }

    // MARK: - Tên & màu mức nhiệt (dùng chung với dòng "Theo dõi nhiệt" ở tab Cài đặt)

    static func levelName(_ level: Int) -> String {
        switch level {
        case 0: return "Bình thường"
        case 1: return "Hơi ấm"
        case 2: return "Nóng"
        case 3: return "Rất nóng"
        default: return "Không rõ"
        }
    }

    static func levelColor(_ level: Int) -> Color {
        switch level {
        case 0: return .green
        case 1: return .yellow
        case 2: return .orange
        default: return .red
        }
    }
}
