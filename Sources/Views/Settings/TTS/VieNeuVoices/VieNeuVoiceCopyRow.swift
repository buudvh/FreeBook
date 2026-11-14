import SwiftUI

/// Hàng **giọng tự tạo chưa có bản ở model kia** trong nhóm "Giọng của tôi" của chip đích (1.3.937, thay
/// `VieNeuTurboCopyRow` của 1.3.901): tên + dòng phụ "Giọng Nano · mẫu 8 s" / "Giọng Turbo · không có mẫu" + nút
/// "Tạo bản Turbo" / "Tạo bản Nano". Đang chạy ⇒ dòng phụ thành bước đang chạy (tải gói %, đọc mẫu, tạo giọng) kèm thanh
/// mảnh — cũng dùng cho lượt của giọng có sẵn (sheet thêm hàng này tạm thời khi lượt đang chạy).
///
/// `onCreate` do sheet quyết (giọng không có mẫu gốc ⇒ hỏi trước).
struct VieNeuVoiceCopyRow: View {
    let source: VieNeuVoiceCopySource
    let entries: [ModelDownloadCenter.Entry]
    let onCreate: () -> Void

    private var runner: VieNeuVoiceCopyRunner { .shared }
    private var isRunningThis: Bool { runner.isRunning(source) }

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
                Text(source.name)
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
                    Text(idleDetail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if !isRunningThis {
                Button("Tạo bản \(source.target.label)", action: onCreate)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.accentColor)
                    .buttonStyle(.borderless)
                    .disabled(runner.isRunning || !VieNeuTurboRuntime.isAvailable)
            }
        }
        .padding(.vertical, 2)
    }

    private var idleDetail: String {
        let sample = source.hasSample ? VieNeuVoiceEntry.sampleDetail(seconds: source.sampleSeconds) : "không có mẫu"
        return ["Giọng \(source.model.label)", sample].compactMap { $0 }.joined(separator: " · ")
    }

    private var progressText: String {
        switch runner.phase {
        case .downloading:
            let total = runner.downloadTotal
            guard total > 0 else { return "Đang tải gói \(source.target.label)…" }
            let done = min(total, VieNeuClonePackages.completedBytes(targets: runner.downloadTargets, in: entries))
            return String(
                format: "Đang tải %d%% · %.0f / %.0f MB",
                Int(Double(done) / Double(total) * 100),
                Double(done) / 1_000_000,
                Double(total) / 1_000_000
            )
        case .speaking:
            return "Đang cho giọng \(source.model.label) đọc mẫu…"
        case .creating, nil:
            return source.target == .turbo
                ? VieNeuCloneStageText.turbo(VieNeuTurboVoiceCloneCoordinator.shared.stage)
                : (VieNeuCloneStageText.nano(runner.nanoStage) ?? "Đang tạo giọng Nano…")
        }
    }
}
