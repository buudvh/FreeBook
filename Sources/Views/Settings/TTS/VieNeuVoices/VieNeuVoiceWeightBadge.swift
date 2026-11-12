import SwiftUI

/// Badge **Nhẹ / Vừa / Nặng** cạnh tên giọng VieNeu (1.3.899): Nhẹ xanh lá (mọi giọng Nano), Vừa cam hổ phách (Turbo),
/// Nặng san hô (Turbo có mẫu dài, `frames` ≥ 85). Màu cố định — không theo màu nhấn (màu nhấn có thể chính là cam).
struct VieNeuVoiceWeightBadge: View {
    let weight: VieNeuVoiceEntry.Weight

    var body: some View {
        Text(weight.title)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 0.5))
            .accessibilityLabel("Mức tốn máy: \(weight.title)")
    }

    private var color: Color {
        switch weight {
        case .light: return Color(red: 0.30, green: 0.80, blue: 0.45)
        case .medium: return Color(red: 1.00, green: 0.70, blue: 0.20)
        case .heavy: return Color(red: 1.00, green: 0.45, blue: 0.40)
        }
    }
}
