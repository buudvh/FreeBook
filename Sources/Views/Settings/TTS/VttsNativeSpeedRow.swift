import SwiftUI

/// Hàng **"vtts tự đọc nhanh tối đa"** (1.3.1037, anh Bửu duyệt mockup) — dùng chung cho Cài đặt TTS (ngay dưới thanh Tốc
/// độ khi trình đọc là vtts) và màn Giọng dự phòng (khi chọn vtts). Cùng khoá `TTSManager.VttsSettings.nativeSpeedMaxKey`.
///
/// Thanh **Tốc độ** vẫn là tốc độ nghe. vtts tự tạo tiếng nhanh tới mức này (`TTSManager.vttsSynthesisSpeed`), phần còn lại
/// để trình phát kéo (`localPlaybackRate` / `remotePlaybackRate`). Dòng dưới thanh chỉ là **số**: "vtts đọc X · trình phát
/// kéo thêm Y" — giải thích nằm sau nút "?" của tiêu đề "Cấu hình giọng nói" (`helpParagraphs`).
///
/// Lưu bằng `@AppStorage` (khoá không dấu chấm) ⇒ nút "Đặt lại" xoá khoá (`VttsSettings.resetNativeSpeedMax`) là hàng tự cập nhật. Đổi giá trị
/// không tự bỏ tiếng đã tạo: giá trị nằm trong `TTSSettingsSnapshot` (trình đọc chính) và fingerprint giọng dự phòng ⇒ đóng
/// Cài đặt là dựng lại đoạn, như khi đổi tốc độ.
struct VttsNativeSpeedRow: View {
    /// Tốc độ nghe đi kèm (thanh Tốc độ của màn đang mở) — chỉ để tính dòng số bên dưới.
    let playbackSpeed: Double

    @AppStorage(TTSManager.VttsSettings.nativeSpeedMaxKey)
    private var storedMaximum = TTSManager.VttsSettings.defaultNativeSpeedMax

    /// Đoạn giải thích sau nút "?" của tiêu đề "Cấu hình giọng nói" khi chọn vtts (Cài đặt TTS + màn Giọng dự phòng).
    static let helpParagraphs: [LocalizedStringKey] = [
        "**Tốc độ** là tốc độ anh nghe. **vtts tự đọc nhanh tối đa**: vtts tự tạo tiếng nhanh tới mức này, phần còn lại để trình phát kéo nhanh.",
        "Tự đọc nhanh nhiều: không có tiếng \"vụt\" ở chỗ nối, nhưng âm điệu khác, kém rõ lời và dễ rè. Để trình phát kéo nhiều (mặc định 1,0x = trình phát kéo cả): rõ lời hơn, có thể có tiếng \"vụt\". Lưu riêng cho vtts, chung với giọng dự phòng."
    ]

    var body: some View {
        let maximum = VttsTTSService.clampedNativeSpeed(storedMaximum)
        let native = VttsTTSService.clampedNativeSpeed(min(playbackSpeed, maximum))
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: maximumBinding, in: VttsTTSService.nativeSpeedRange, step: 0.1) {
                HStack {
                    Text("vtts tự đọc nhanh tối đa:")
                    Spacer()
                    Text(String(format: "%.1fx", maximum))
                        .font(.system(.body, design: .monospaced))
                }
            }
            Slider(value: maximumBinding, in: VttsTTSService.nativeSpeedRange, step: 0.1)
            Text("vtts đọc \(Self.decimal(native))x · trình phát kéo thêm \(Self.decimal(playbackSpeed / native))x")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// Bước 0,1 cộng dồn số thực ra kiểu 1.4000000000000001 ⇒ làm tròn 1 chữ số khi lưu (như `VieNeuSynthesisSpeedRow`).
    private var maximumBinding: Binding<Double> {
        Binding(
            get: { VttsTTSService.clampedNativeSpeed(storedMaximum) },
            set: { storedMaximum = (VttsTTSService.clampedNativeSpeed($0) * 10).rounded() / 10 }
        )
    }

    /// "1,29" — dấu phẩy thập phân như chữ trong mockup.
    private static func decimal(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }
}
