import SwiftUI

/// Hàng **"Tốc độ tổng hợp (VieNeu)"** của Nano — dùng chung cho Cài đặt TTS và màn Giọng dự phòng (1.3.961, trước đó
/// hai màn chép riêng một bản). Cùng khoá `VieNeuSynthesisPolicy.synthesisSpeedKey`.
///
/// Khác thanh Tốc độ ở chỗ: giá trị này **đưa vào model** (`secs = exp(log_s)/speed`), không phải tăng tốc lúc phát. Tốc
/// độ nghe = **tích** hai thanh, nên bắt buộc phải hiện tích đó — nếu không, kéo thanh này lên 1,8× trong khi thanh Tốc độ
/// đang 1,8× sẽ thành **3,24×** mà người dùng không hề hay biết (dòng tóm tắt đổi màu khi vượt 2,0×).
struct VieNeuSynthesisSpeedRow: View {
    @Binding var synthesisSpeed: Double
    /// Tốc độ phát đi kèm (thanh Tốc độ của màn đang mở) — chỉ để tính "Tốc độ nghe thực tế".
    let playbackSpeed: Double
    /// Sau khi lưu giá trị mới (Cài đặt TTS bỏ phần đệm đã tổng hợp ở tốc độ cũ).
    var onSaved: () -> Void = {}

    var body: some View {
        let effective = synthesisSpeed * playbackSpeed
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: $synthesisSpeed, in: VieNeuSynthesisPolicy.synthesisSpeedRange, step: 0.05) {
                HStack {
                    Text("Tốc độ tổng hợp (VieNeu):")
                    Spacer()
                    Text(String(format: "%.2fx", synthesisSpeed))
                        .font(.system(.body, design: .monospaced))
                }
            }
            Slider(value: $synthesisSpeed, in: VieNeuSynthesisPolicy.synthesisSpeedRange, step: 0.05)
            HStack(spacing: 4) {
                Text("Tốc độ nghe thực tế:")
                Text(String(format: "%.2fx", effective))
                    .font(.system(.body, design: .monospaced))
                    // `.orange` là màu cảnh báo literal có chủ ý: màu nhấn do người dùng chọn (có thể chính là Cam hổ
                    // phách) ⇒ cảnh báo lẫn với màu nhấn.
                    .foregroundColor(effective > 2.0 ? .orange : .primary)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .onChange(of: synthesisSpeed) { _, newValue in
            // Bước 0,05 cộng dồn số thực ra kiểu 1.1500000000000001 ⇒ làm tròn 2 chữ số khi lưu (1.3.502).
            UserDefaults.standard.set((newValue * 100).rounded() / 100, forKey: VieNeuSynthesisPolicy.synthesisSpeedKey)
            onSaved()
        }
    }
}
