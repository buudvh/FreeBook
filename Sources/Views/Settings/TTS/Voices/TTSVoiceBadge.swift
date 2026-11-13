import SwiftUI

/// Badge nhỏ cạnh tên giọng ở sheet chọn giọng và hàng "Giọng đọc" của Cài đặt TTS: chữ + màu **cố định** (không theo màu
/// nhấn — màu nhấn có thể trùng màu badge), nền mờ, viền mảnh. VieNeu dùng qua `VieNeuVoiceWeightBadge` (Nhẹ / Vừa /
/// Nặng); Siri và NghiTTS là "Nhẹ" (chạy trên máy), Google và tiện ích là "Online".
struct TTSVoiceBadge: View {
    /// Xanh lá của "Nhẹ" — chung cho VieNeu Nano, Siri, NghiTTS.
    static let lightColor = Color(red: 0.30, green: 0.80, blue: 0.45)
    /// Xanh dương của "Online" — Google, tiện ích.
    static let onlineColor = Color(red: 0.37, green: 0.66, blue: 1.0)

    static var light: TTSVoiceBadge {
        TTSVoiceBadge(title: "Nhẹ", color: lightColor, accessibilityText: "Mức tốn máy: Nhẹ")
    }

    static var online: TTSVoiceBadge {
        TTSVoiceBadge(title: "Online", color: onlineColor, accessibilityText: "Giọng đọc qua mạng")
    }

    let title: String
    let color: Color
    let accessibilityText: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 0.5))
            .accessibilityLabel(accessibilityText)
    }
}
