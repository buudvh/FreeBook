import SwiftUI

/// Viên nhỏ **"model · tăng tốc"** của đoạn đang phát ở sheet điều khiển nhanh TTS (1.3.942, anh Bửu duyệt mockup), cạnh
/// badge nhiệt (`TTSThermalBadge`): "Turbo · AMX" / "Nano · Core ML" màu lam khi đang tăng tốc, "Turbo · CPU" /
/// "Nano · CPU" màu xám khi AMX tự tắt hoặc Core ML chưa sẵn / lùi ORT. Đọc lai Nano · Turbo ⇒ đổi theo từng đoạn.
/// Nhãn lấy từ `VieNeuEngineBadgeStore` qua `TTSQuickControlNowReading` (một lần tra mỗi đoạn) — không bấm được.
struct TTSEngineBadge: View {
    let label: VieNeuEngineBadgeStore.Label

    var body: some View {
        let color = label.accelerated ? Color.cyan : Color.secondary
        HStack(spacing: 3) {
            Image(systemName: label.accelerated ? "bolt.fill" : "cpu")
                .font(.system(size: 10, weight: .semibold))
            Text(label.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(label.accelerated ? 0.18 : 0.2), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Đang đọc bằng \(label.title)")
    }
}
