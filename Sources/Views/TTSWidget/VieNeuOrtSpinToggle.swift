import SwiftUI

/// Công tắc cho luồng ORT của VieNeu **chờ bận (spin)** giữa các lượt tính (`session.intra_op.allow_spinning`).
///
/// Mặc định **tắt** (1.3.488). Bật: luồng pool quay vòng một lúc chờ việc thay vì ngủ ngay ⇒ tốn CPU, nóng máy;
/// đo trên iPhone (2 luồng) không nhanh hơn (RTF 0,38 bật / 0,32 tắt), audio giống hệt từng bit. Mô tả UI
/// nói đúng tác dụng của **trạng thái bật** vì nhãn công tắc là trạng thái bật (1.3.509).
/// View riêng (có `@AppStorage` của mình) để không thêm state vào `TTSSettingsView`.
struct VieNeuOrtSpinToggle: View {
    @AppStorage(VieNeuSynthesisPolicy.allowSpinningKey) private var allowSpinning = false

    var body: some View {
        Toggle("Luồng tổng hợp chờ bận (spin)", isOn: $allowSpinning)
        Text("Bật: luồng quay vòng chờ việc thay vì ngủ ngay, tốn CPU và nóng máy hơn mà không nhanh hơn. Nên để tắt.")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
