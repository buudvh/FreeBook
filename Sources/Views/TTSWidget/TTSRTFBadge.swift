import SwiftUI

/// Viên nhỏ **"RTF 0.32"** ở sheet điều khiển nhanh TTS (1.3.954): tốc độ tổng hợp của đoạn đang phát —
/// **VieNeu** (Nano/Turbo) hoặc **Piper / NghiTTS**.
///
/// RTF = thời gian tổng hợp ÷ thời lượng **lời đọc** (không tính khoảng lặng chèn thêm, 1.3.958): 0,32 là nhanh ~3×
/// thời gian thực, 1,24 là chậm hơn thời gian thực.
/// Màu theo ngưỡng như badge nhiệt: ≤ 0,5 xanh · 0,5–1,0 vàng · > 1,0 đỏ. Không bấm được.
struct TTSRTFBadge: View {
    let rtf: Double

    var body: some View {
        let color = Self.color(for: rtf)
        HStack(spacing: 3) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 10, weight: .semibold))
            Text("RTF \(String(format: "%.2f", rtf))")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.18), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tốc độ tổng hợp: RTF \(String(format: "%.2f", rtf))")
    }

    /// ≤ 0,5 xanh · 0,5–1,0 vàng · > 1,0 đỏ.
    private static func color(for rtf: Double) -> Color {
        if rtf <= 0.5 { return .green }
        if rtf <= 1.0 { return .yellow }
        return .red
    }
}
