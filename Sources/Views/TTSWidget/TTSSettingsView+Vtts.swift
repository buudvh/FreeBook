import SwiftUI

/// Phần **vtts Việt–Anh** của màn Cài đặt TTS (2026-11-20, mockup anh Bửu duyệt). Theo mockup, khi chọn vtts màn chỉ có:
/// Picker "Trình đọc" (mục `vttsPickerRow`), "Giọng đọc" (hàng chung `TTSReaderVoiceSummaryRow` ⇒ sheet chọn giọng chung,
/// `TTSVoiceEngine.vtts`), "Quản lý riêng của trình đọc" (chỉ hàng chung "Phiên âm tiếng Nhật"), "Cấu hình giọng nói" như
/// cũ, và "Tải trước dữ liệu" chỉ một hàng độ dài phân đoạn (`vttsPrefetchSection`).
///
/// Tách file theo khuôn `X+Feature.swift` như `+VieNeu` — file chính chỉ thêm lời gọi.
extension TTSSettingsView {
    /// Mục vtts của Picker "Trình đọc" — ngay sau mục VieNeu.
    var vttsPickerRow: some View {
        Text("vtts Việt–Anh (Offline)").tag(TTSManager.VttsSettings.tool)
    }

    /// Nút "?" của tiêu đề "Cấu hình giọng nói" khi chọn vtts (1.3.1037) — giải thích hàng "vtts tự đọc nhanh tối đa".
    var vttsVoiceSectionHelp: some View {
        SectionHelpButton(
            accessibilityLabel: "Giải thích Cấu hình giọng nói",
            paragraphs: VttsNativeSpeedRow.helpParagraphs + [TTSVolumeRow.helpParagraph]
        )
    }

    /// Nút "Đặt lại" của "Cấu hình giọng nói": trình đọc là vtts ⇒ "vtts tự đọc nhanh tối đa" về mặc định (`@AppStorage` của
    /// hàng tự cập nhật). Trình đọc khác ⇒ không đụng.
    func resetVttsNativeSpeedMax() {
        guard ttsManager.tool == TTSManager.VttsSettings.tool else { return }
        UserDefaults.standard.set(TTSManager.VttsSettings.defaultNativeSpeedMax, forKey: TTSManager.VttsSettings.nativeSpeedMaxKey)
    }

    /// "Tải trước dữ liệu" của vtts: chỉ **độ dài phân đoạn** (khoá `vttsChunk`, mặc định 500 từ 1.3.1035). Có tác dụng thật —
    /// `TTSManager.playbackParagraphs` cắt đoạn của engine local bằng `NghiUtteranceSegmenter` theo `chunkLength`. Không có
    /// số đoạn tải trước (engine local nạp theo ngưỡng giây, không theo số đoạn) và ngưỡng đệm dùng chung NghiTTS.
    var vttsPrefetchSection: some View {
        Stepper(value: $ttsManager.chunkLength, in: 50...500, step: 10) {
            HStack {
                Text("Độ dài phân đoạn (vtts):")
                Spacer()
                Text("\(ttsManager.chunkLength) ký tự")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }
}
