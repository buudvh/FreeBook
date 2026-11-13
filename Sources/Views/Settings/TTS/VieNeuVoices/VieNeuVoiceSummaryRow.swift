import SwiftUI

/// Hàng **"Giọng đọc"** của Cài đặt TTS khi trình đọc là VieNeu (1.3.900): vòng tròn icon, tên giọng đang đọc + nhãn nhỏ
/// "Nano" / "Turbo", dòng phụ thông tin, badge Nhẹ / Vừa / Nặng, chevron. Bấm ⇒ sheet chọn giọng (`onTap`).
///
/// Giọng hiển thị = giọng trình đọc **đang dùng** (model hiệu lực + `selectedVoice`): lựa chọn Turbo mà máy thiếu file
/// Turbo thì hiện giọng Nano đang thay. Chưa tải dữ liệu của giọng đó ⇒ dòng phụ cam "Chưa tải dữ liệu giọng".
struct VieNeuVoiceSummaryRow: View {
    let onTap: () -> Void

    @ObservedObject private var ttsManager = TTSManager.shared

    private var directory: VieNeuVoiceDirectory { .shared }

    var body: some View {
        let selection = displayedSelection
        let entry = directory.entry(for: selection)
        let isReady = entry.map { directory.isReady($0) } ?? false
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.18))
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry?.name ?? selection.voiceId)
                            .font(.body)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        modelTag(selection.model)
                    }
                    // Lần vẽ đầu (trước khi đọc đĩa xong) chưa biết đã tải hay chưa ⇒ chưa hiện cảnh báo.
                    if isReady || !directory.hasLoaded {
                        // Nano đang chuẩn bị Tăng tốc Core ML (luôn bật, 1.3.919) ⇒ hiện bước đang chạy thay thông tin giọng.
                        if selection.model == .nano, let stage = VieNeuCoreMLAccelerator.shared.stageText {
                            Text(stage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                        } else if let detail = entry?.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        // `.orange` literal có chủ ý: cảnh báo, không theo màu nhấn.
                        Text("Chưa tải dữ liệu giọng · chạm để tải")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VieNeuVoiceWeightBadge(weight: entry?.weight ?? (selection.model == .nano ? .light : .medium))
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { directory.reload() }
    }

    private var displayedSelection: VieNeuVoiceSelection {
        Self.displayedSelection(tool: ttsManager.tool, selectedVoice: ttsManager.selectedVoice)
    }

    /// Giọng trình đọc đang dùng; giọng rỗng (Nano chưa tải catalog) ⇒ giọng mặc định của model để vẫn có tên mà hiện.
    /// Trang Cài đặt VieNeu TTS (`VieNeuTTSSettingsView`) dùng chung.
    static func displayedSelection(tool: String, selectedVoice: String) -> VieNeuVoiceSelection {
        let model = VieNeuModelChoice.current
        var voiceId = tool == "vieneu" ? selectedVoice : ""
        if voiceId.isEmpty {
            let stored = VieNeuVoiceSelection.stored
            voiceId = stored.model == model ? stored.voiceId : ""
        }
        if voiceId.isEmpty {
            voiceId = model == .nano ? VieNeuBuiltinVoiceList.nanoDefaultName : VieNeuTurboModelStore.fallbackVoiceId
        }
        return VieNeuVoiceSelection(model: model, voiceId: voiceId)
    }

    private func modelTag(_ model: VieNeuModelChoice) -> some View {
        Text(model.label)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.primary.opacity(0.08), in: Capsule())
    }
}
