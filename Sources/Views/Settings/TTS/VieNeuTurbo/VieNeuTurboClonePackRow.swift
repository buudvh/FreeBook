import SwiftUI

/// Hàng **gói nhân bản giọng Turbo** (`speaker_encoder.onnx` + `denoiser.onnx`, ~71 MB) trong mục "Tạo giọng Turbo từ
/// file" của màn thử (1.3.893): trạng thái, nút tải (qua `ModelDownloadCenter` nên rời màn vẫn tải tiếp), tiến độ, nút
/// xoá. Quan sát `ModelDownloadCenter` ở đây để lượt tải xong là mục tạo giọng tự kiểm lại điều kiện.
struct VieNeuTurboClonePackRow: View {
    @ObservedObject private var center = ModelDownloadCenter.shared
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    var body: some View {
        let entry = center.entry(id: VieNeuTurboClonePack.downloadTarget)
        Group {
            if let entry, entry.state.isRunning {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.message.isEmpty ? "Đang tải gói nhân bản giọng…" : entry.message)
                        .font(.caption)
                    if let fraction = entry.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                    }
                }
            } else if VieNeuTurboClonePack.isReady {
                LabeledContent(
                    "Gói nhân bản",
                    value: "Đã tải · \(VieNeuTurboLabView.formattedBytes(VieNeuTurboClonePack.bytesOnDisk))"
                )
                Button(role: .destructive) {
                    try? VieNeuTurboClonePack.delete()
                    onChange()
                } label: {
                    Label("Xoá gói nhân bản giọng", systemImage: "trash")
                }
                .disabled(VieNeuTurboVoiceCloneCoordinator.shared.isRunning)
            } else {
                LabeledContent("Gói nhân bản", value: "Thiếu \(VieNeuTurboClonePack.missingNames.joined(separator: ", "))")
                Button {
                    VieNeuTurboClonePack.download()
                } label: {
                    Label(
                        "Tải gói nhân bản giọng (\(VieNeuTurboLabView.formattedBytes(VieNeuTurboClonePack.byteCount)))",
                        systemImage: "arrow.down.circle"
                    )
                }
                .buttonStyle(.appFilled)
            }
            if let entry, case .failed(let message) = entry.state {
                Text("Tải lỗi: \(message)")
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }
        }
        .onChange(of: center.entries) { _, _ in onChange() }
    }
}
