import SwiftUI

/// Hàng **giọng Nano tự tạo chưa có bản Turbo** trong nhóm "Giọng của tôi" của chip Turbo (1.3.900): tên + dòng phụ
/// "Giọng Nano · mẫu 8 s" + nút "Tạo bản Turbo" (`VieNeuTurboCopyRunner`). Đang chạy ⇒ dòng phụ thành tiến độ tải gói /
/// "Đang tạo bản Turbo…" kèm thanh mảnh.
struct VieNeuTurboCopyRow: View {
    let voice: VieNeuVoiceDirectory.NanoOnlyVoice
    let entries: [ModelDownloadCenter.Entry]

    private var runner: VieNeuTurboCopyRunner { .shared }
    private var isRunningThis: Bool { runner.runningNanoId == voice.id }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.10))
                Image(systemName: "person.wave.2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(voice.name)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if isRunningThis {
                    Text(progressText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    ProgressView()
                        .progressViewStyle(.linear)
                        .scaleEffect(x: 1, y: 0.6, anchor: .center)
                } else {
                    Text(["Giọng Nano", VieNeuVoiceEntry.sampleDetail(seconds: voice.sampleSeconds)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if !isRunningThis {
                Button("Tạo bản Turbo") { runner.run(voice) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.accentColor)
                    .buttonStyle(.borderless)
                    .disabled(runner.isRunning || !voice.hasSample || !VieNeuTurboRuntime.isAvailable)
            }
        }
        .padding(.vertical, 2)
    }

    private var progressText: String {
        switch runner.phase {
        case .downloading:
            let total = runner.downloadTotal
            guard total > 0 else { return "Đang tải gói Turbo…" }
            let done = min(total, VieNeuClonePackages.completedBytes(targets: runner.downloadTargets, in: entries))
            return String(
                format: "Đang tải %d%% · %.0f / %.0f MB",
                Int(Double(done) / Double(total) * 100),
                Double(done) / 1_000_000,
                Double(total) / 1_000_000
            )
        case .creating, nil:
            return VieNeuTurboLabView.cloneStageText(VieNeuTurboVoiceCloneCoordinator.shared.stage)
        }
    }
}
