import SwiftUI

/// Hàng **"Âm lượng"** (1.3.1047, anh Bửu duyệt mockup https://claude.ai/artifact/SiAJyQbt7tgWohnCJesDcg) — cuối nhóm "Cấu
/// hình giọng nói" (trước Cao độ) khi trình đọc là vtts / NghiTTS / VieNeu, ở Cài đặt TTS và màn Giọng dự phòng.
///
/// Số dB to / nhỏ hơn mức app vẫn kéo cho **giọng đang chọn** (`TTSVolumeSettings`, lưu riêng từng giọng; 0 = như trước).
/// Dòng dưới thanh chỉ là số: "<giọng> · mặc định <dB>" — giải thích nằm sau nút "?" của tiêu đề (`helpParagraph`).
/// `@AppStorage` của bảng lưu ⇒ "Đặt lại" (`reset`) ghi thẳng là hàng tự cập nhật. Đổi mức không tự bỏ tiếng đã tạo: mức nằm
/// trong `TTSSettingsSnapshot` / fingerprint giọng dự phòng ⇒ đóng Cài đặt là dựng lại đoạn; ▶ thử giọng nghe đúng mức mới.
struct TTSVolumeRow: View {
    /// `TTSManager.tool` của trình đọc (`vtts` / `nghitts` / `vieneu`).
    let tool: String
    /// Giọng đúng như chuỗi service nhận (`selectedVoice`, `TTSManager.onlineFallbackVoice(for:)`).
    let voice: String

    @AppStorage(TTSVolumeSettings.defaultsKey) private var storedTable = ""

    static let helpParagraph: LocalizedStringKey =
        "**Âm lượng**: to / nhỏ hơn mức app kéo chuẩn cho giọng này (0 dB). Kéo to quá dễ rè: đỉnh tiếng bị ghìm mềm dưới −1 dB, ghìm càng nhiều càng rè — vì vậy giọng vtts mặc định −6 dB. Lưu riêng từng giọng; Đặt lại về mức mặc định."

    var body: some View {
        if let target = Self.target(tool: tool, voice: voice) {
            let _ = storedTable // đọc để hàng vẽ lại khi bảng lưu đổi
            let value = TTSVolumeSettings.offset(engine: target.engine, voiceKey: target.voiceKey)
            let defaultValue = TTSVolumeSettings.defaultOffset(engine: target.engine, voiceKey: target.voiceKey)
            VStack(alignment: .leading, spacing: 6) {
                Stepper(value: binding(target), in: TTSVolumeSettings.range, step: 1) {
                    HStack {
                        Text("Âm lượng:")
                        Spacer()
                        Text(Self.decibels(value))
                            .font(.system(.body, design: .monospaced))
                    }
                }
                Slider(value: sliderBinding(target), in: Self.sliderRange, step: 1)
                Text("\(target.name) · mặc định \(Self.decibels(defaultValue))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Nút "Đặt lại" của "Cấu hình giọng nói": giọng đang chọn về mức mặc định của nó.
    static func reset(tool: String, voice: String) {
        guard let target = target(tool: tool, voice: voice) else { return }
        TTSVolumeSettings.set(
            TTSVolumeSettings.defaultOffset(engine: target.engine, voiceKey: target.voiceKey),
            engine: target.engine, voiceKey: target.voiceKey
        )
    }

    /// "0 dB", "+2 dB", "−3 dB".
    static func decibels(_ value: Int) -> String {
        value == 0 ? "0 dB" : value > 0 ? "+\(value) dB" : "−\(-value) dB"
    }

    // MARK: - Nội bộ

    private struct Target {
        let engine: TTSVolumeSettings.Engine
        let voiceKey: String
        let name: String
    }

    private static let sliderRange = Double(TTSVolumeSettings.range.lowerBound)...Double(TTSVolumeSettings.range.upperBound)

    private static func target(tool: String, voice: String) -> Target? {
        guard let engine = TTSVolumeSettings.Engine(rawValue: tool) else { return nil }
        let key = TTSVolumeSettings.voiceKey(engine: engine, voice: voice)
        switch engine {
        case .vtts:
            return Target(engine: engine, voiceKey: key, name: VttsVoice.resolve(voice).displayName)
        case .nghitts:
            return Target(engine: engine, voiceKey: key, name: voice.isEmpty ? "Giọng mặc định" : voice)
        case .vieneu:
            let selection = VieNeuVoiceSelection(model: VieNeuModelChoice.current, voiceId: voice)
            let name = VieNeuVoiceDirectory.shared.entry(for: selection)?.name ?? voice
            return Target(engine: engine, voiceKey: key, name: name.isEmpty ? "Giọng mặc định" : name)
        }
    }

    private func binding(_ target: Target) -> Binding<Int> {
        Binding(
            get: { TTSVolumeSettings.offset(engine: target.engine, voiceKey: target.voiceKey) },
            set: { TTSVolumeSettings.set($0, engine: target.engine, voiceKey: target.voiceKey) }
        )
    }

    private func sliderBinding(_ target: Target) -> Binding<Double> {
        Binding(
            get: { Double(TTSVolumeSettings.offset(engine: target.engine, voiceKey: target.voiceKey)) },
            set: { TTSVolumeSettings.set(Int($0.rounded()), engine: target.engine, voiceKey: target.voiceKey) }
        )
    }
}
