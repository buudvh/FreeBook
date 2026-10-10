import SwiftUI

/// Công tắc **Chống đọc lặp** của VieNeu (1.3.501) — mặc định **bật**.
///
/// Bật: model nói nhanh tối thiểu `VieNeuSynthesisPolicy.antiRepeatModelSpeedFloor` (1,15×) rồi app phát chậm
/// lại đúng tỉ lệ ⇒ tốc độ nghe không đổi, lỗi đọc lặp một âm tiết giảm ~85 % (đo 200 mẫu/mức), bớt ~13 % CPU.
/// Đổi công tắc thì đoạn đang phát giữ nguyên, các đoạn sau tổng hợp lại (`invalidateVieNeuSynthesisSpeed`).
/// View riêng (có `@AppStorage` của mình) để không thêm state vào `TTSSettingsView`.
struct VieNeuAntiRepeatToggle: View {
    @AppStorage(VieNeuSynthesisPolicy.antiRepeatKey) private var antiRepeat = true

    var body: some View {
        Toggle("Chống đọc lặp", isOn: $antiRepeat)
            .onChange(of: antiRepeat) { _, _ in
                TTSManager.shared.invalidateVieNeuSynthesisSpeed()
            }
        Text("Bật (mặc định): model nói nhanh hơn một chút (tối thiểu 1,15x) rồi app phát chậm lại đúng tỉ lệ — tốc độ nghe không đổi nhưng gần như hết lỗi đọc lặp chữ (\"đến đó, đó là\"), máy mát hơn khoảng 13 %. Không tác dụng thêm khi tốc độ tổng hợp đã từ 1,15x trở lên.")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
