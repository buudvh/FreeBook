import Combine
import SwiftUI

/// Viên nhỏ báo **mức nhiệt của máy** ở sheet điều khiển nhanh TTS (1.3.931, anh Bửu duyệt mockup): icon nhiệt kế +
/// "Mát" / "Ấm" / "Nóng" / "Rất nóng", chữ xanh / vàng / cam / đỏ trên nền cùng màu 18%. Nằm bên trái "N/M" dưới vạch
/// tiến độ chương (`TTSQuickControlSheet.NowReadingBlock`).
///
/// iOS không cho đọc °C — chỉ `ProcessInfo.thermalState` (nominal / fair / serious / critical; cùng nguồn với trường
/// `thermal=` của log TTS). Đổi ngay khi iOS báo `thermalStateDidChangeNotification` (bắn ở luồng bất kỳ ⇒ nhận trên
/// main). Không bấm được.
struct TTSThermalBadge: View {
    @State private var state = ProcessInfo.processInfo.thermalState

    var body: some View {
        let style = Self.style(for: state)
        HStack(spacing: 3) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 10, weight: .semibold))
            Text(style.title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(style.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(style.color.opacity(0.18), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nhiệt độ máy: \(style.title)")
        .onAppear { state = ProcessInfo.processInfo.thermalState }
        .onReceive(
            NotificationCenter.default
                .publisher(for: ProcessInfo.thermalStateDidChangeNotification)
                .receive(on: DispatchQueue.main)
        ) { _ in
            state = ProcessInfo.processInfo.thermalState
        }
    }

    private static func style(for state: ProcessInfo.ThermalState) -> (title: String, color: Color) {
        switch state {
        case .nominal: return ("Mát", Color.green)
        case .fair: return ("Ấm", Color.yellow)
        case .serious: return ("Nóng", Color.orange)
        case .critical: return ("Rất nóng", Color.red)
        @unknown default: return ("Không rõ", Color.secondary)
        }
    }
}
