import SwiftUI

/// Phần **VieNeu Turbo** của màn Cài đặt TTS: selection của Picker "Trình đọc", cảnh báo tốc độ và nút "?" của section
/// "Cấu hình giọng nói". Giọng (cả Nano lẫn Turbo) chọn ở sheet chọn giọng từ 1.3.900.
///
/// Tách file riêng vì `TTSSettingsView.swift` là file legacy chỉ được giảm dòng — ở đó chỉ đổi đúng một dòng (selection
/// của Picker "Trình đọc"); `+VieNeu` / `+Voice` chỉ thêm lời gọi tới các khối ở đây.
///
/// Bên trong vẫn là `tool == "vieneu"`: model là phần của giọng đang chọn (`VieNeuVoiceSelection`).
extension TTSSettingsView {
    /// Turbo đang là trình đọc (model **hiệu lực**, đã xét máy có đủ file).
    var isVieNeuTurboSelected: Bool {
        ttsManager.tool == "vieneu" && VieNeuModelChoice.current == .turbo
    }

    // MARK: - Picker "Trình đọc"

    /// Selection của Picker "Trình đọc" — từ 1.3.898 chỉ còn **một** mục VieNeu (`tool = "vieneu"`), model đi theo giọng.
    var readerPickerSelection: Binding<String> {
        Binding(get: { ttsManager.tool }, set: { ttsManager.tool = $0 })
    }

    // MARK: - Cấu hình giọng nói

    /// Dưới thanh Tốc độ khi giọng đang chọn là Turbo: **chỉ** cảnh báo cam khi vượt mức Turbo tổng hợp kịp. Giải thích
    /// (Turbo không có tốc độ tổng hợp) nằm sau nút "?" của section (`voiceSectionHelp`).
    @ViewBuilder
    var vieNeuTurboSpeedNotes: some View {
        let limit = VieNeuTurboTTSService.realtimeSpeedLimit
        // `+ 0.001`: bước 0,1 cộng dồn số thực ra kiểu 2.0000000000000004 — không được tính là vượt mức.
        if ttsManager.speed > limit + 0.001 {
            Label {
                Text("Turbo theo kịp tới khoảng \(Self.speedText(limit))×. Ở \(Self.speedText(ttsManager.speed))× có thể hụt tiếng, nhất là khi máy nóng.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            // `.orange` literal có chủ ý (như cảnh báo tốc độ nghe của Nano): màu nhấn do người dùng chọn có thể là cam.
            .foregroundColor(.orange)
        }
    }

    /// Nút "?" của section "Cấu hình giọng nói" khi trình đọc là VieNeu.
    var voiceSectionHelp: some View {
        SectionHelpButton(accessibilityLabel: "Giải thích Cấu hình giọng nói", paragraphs: [
            "Turbo luôn tổng hợp ở tốc độ gốc, tốc độ nghe chỉnh bằng thanh Tốc độ. Turbo theo kịp tới khoảng 2,0×. Giọng Nano có thêm Tốc độ tổng hợp.",
            "Tốc độ tổng hợp (Nano): model nói nhanh hơn, máy mát hơn. 1,15× ít lặp chữ nhất, quá 1,25× mất chữ. Tốc độ nghe thực tế = tốc độ tổng hợp × Tốc độ."
        ])
    }

    /// "1,6" — dấu phẩy thập phân như chữ trong mockup.
    static func speedText(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
