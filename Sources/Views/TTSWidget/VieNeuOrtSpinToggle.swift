import SwiftUI

/// Công tắc cho luồng ORT của VieNeu **chờ bận (spin)** giữa các lượt tính — để đo A/B năng lượng trên máy thật.
///
/// Mặc định **tắt** (1.3.488): spin giữ luồng pool quay rỗng giữa các op ⇒ tốn CPU-time mà gần như không đổi
/// tốc độ. Bật lại để so với hành vi cũ bằng `[VieNeuPerf] cpu=…` và `[NghiEnergy] … cpuPerAudioSec=…`.
/// View riêng (có `@AppStorage` của mình) để không thêm state vào `TTSSettingsView`.
struct VieNeuOrtSpinToggle: View {
    @AppStorage(VieNeuSynthesisPolicy.allowSpinningKey) private var allowSpinning = false

    var body: some View {
        Toggle("Luồng tổng hợp chờ bận (spin)", isOn: $allowSpinning)
        Text("Tắt (mặc định) để luồng ngủ khi rảnh — tốn ít CPU và mát máy hơn, tốc độ gần như không đổi. Bật chỉ để so sánh với cách chạy cũ. Áp dụng sau khi tắt hẳn app rồi mở lại.")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
