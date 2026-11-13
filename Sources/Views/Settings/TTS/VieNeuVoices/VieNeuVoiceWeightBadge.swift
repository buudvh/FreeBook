import SwiftUI

/// Badge **Nhẹ / Vừa / Nặng** cạnh tên giọng VieNeu (1.3.900): Nhẹ xanh lá (mọi giọng Nano), Vừa cam hổ phách (Turbo),
/// Nặng san hô (Turbo có mẫu dài, `frames` ≥ 85). Màu cố định — không theo màu nhấn (màu nhấn có thể chính là cam). Vẽ
/// bằng badge chung `TTSVoiceBadge` (cùng dáng với badge của Siri / NghiTTS / Google / tiện ích).
struct VieNeuVoiceWeightBadge: View {
    let weight: VieNeuVoiceEntry.Weight

    var body: some View {
        TTSVoiceBadge(title: weight.title, color: color, accessibilityText: "Mức tốn máy: \(weight.title)")
    }

    private var color: Color {
        switch weight {
        case .light: return TTSVoiceBadge.lightColor
        case .medium: return Color(red: 1.00, green: 0.70, blue: 0.20)
        case .heavy: return Color(red: 1.00, green: 0.45, blue: 0.40)
        }
    }
}
