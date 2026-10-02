import SwiftUI

/// Phần **Cấu hình giọng nói** (Section 4) của màn Cài đặt TTS.
///
/// Tách khỏi `TTSSettingsView.swift` ở 1.3.465 vì file đó đang **chạm trần** allowlist (519/519 dòng) mà
/// lượt này phải **thêm** một hàng (thanh "Tốc độ tổng hợp" của VieNeu) vào đúng section này. Chuyển
/// nguyên khối ra đây ⇒ file chính **giảm** dòng thay vì tăng. Cùng khuôn đã dùng cho
/// `TTSSettingsView+VieNeu.swift` và `TTSSettingsView+NumberPreprocessing.swift`.
///
/// Hệ quả của việc tách file: `showingReplacementManagerSheet` phải hạ `private` → `internal`
/// (Swift giới hạn `private` theo file).
extension TTSSettingsView {
    /// Tốc độ / cao độ và — với VieNeu — tốc độ **tổng hợp**.
    @ViewBuilder
    var voiceSection: some View {
        Section(header: HStack {
            Text("Cấu hình giọng nói")
            Spacer()
            Button(action: {
                ttsManager.speed = 1.0
                ttsManager.pitch = 1.0
                resetVieNeuSynthesisSpeed()
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Đặt lại")
                }
                .font(.caption)
                .foregroundColor(.white)
            }
        }) {
            Button(action: { showingReplacementManagerSheet = true }) {
                HStack {
                    Label("Quản lý thay thế ký tự", systemImage: "pencil.and.outline")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Stepper(value: $ttsManager.speed, in: 0.5...5.0, step: 0.1) {
                    HStack {
                        Text("Tốc độ:")
                        Spacer()
                        Text(String(format: "%.1fx", ttsManager.speed))
                            .font(.system(.body, design: .monospaced))
                    }
                }
                Slider(value: $ttsManager.speed, in: 0.5...5.0, step: 0.1)
                    .tint(.white)
            }

            // Thanh riêng của VieNeu: đặt **cạnh** thanh Tốc độ để hai thứ cộng hưởng vào nhau được nhìn
            // thấy ngay (tốc độ nghe = tổng hợp × phát). Chỉ hiện khi đang chọn VieNeu.
            if ttsManager.tool == "vieneu" {
                vieneuSynthesisSpeedRow
            }

            let isExtensionTool = TTSManager.isExtensionTool(ttsManager.tool)
            // Engine local (NghiTTS + VieNeu) phat qua `NghiAudioPlayerQueue`, ma queue nay chi co
            // `updateRate(_:)` — khong co `AVAudioUnitTimePitch`. Nen pitch la **no-op** voi ca hai.
            let disablePitch = TTSManager.isLocalEngine(ttsManager.tool) || isExtensionTool

            VStack(alignment: .leading, spacing: 6) {
                Stepper(value: $ttsManager.pitch, in: 0.5...2.0, step: 0.1) {
                    HStack {
                        Text("Cao độ (Pitch):")
                        Spacer()
                        Text(String(format: "%.1fx", ttsManager.pitch))
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .disabled(disablePitch)

                Slider(value: $ttsManager.pitch, in: 0.5...2.0, step: 0.1)
                    .tint(.white)
                    .disabled(disablePitch)
                if TTSManager.isLocalEngine(ttsManager.tool) {
                    Text("(*) Engine offline (NghiTTS/VieNeu) không hỗ trợ chỉnh cao độ thời gian thực")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if isExtensionTool {
                    Text("(*) Extension TTS không hỗ trợ chỉnh cao độ")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
