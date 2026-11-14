import SwiftUI

/// Viên nhỏ **"Dự phòng"** ở sheet điều khiển nhanh TTS (1.3.945): đoạn đang phát do giọng dự phòng đọc vì TTS online lỗi /
/// mất mạng. Cam (`.orange` literal có chủ ý — trạng thái cảnh báo, không theo màu nhấn). VieNeu ⇒ kèm badge "model · tăng
/// tốc" (`TTSEngineBadge`) ngay sau; NghiTTS ⇒ ghi tên engine trong viên này. Không bấm được.
struct TTSFallbackBadge: View {
    let engine: TTSOnlineFallbackSettings.Engine

    var body: some View {
        let title = engine == .vieneu ? "Dự phòng" : "Dự phòng · \(engine.title)"
        HStack(spacing: 3) {
            Image(systemName: "lifepreserver")
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.orange)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.18), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Đang đọc bằng giọng dự phòng \(engine.title)")
    }
}
