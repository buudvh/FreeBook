import SwiftUI

/// Mục **"Tạo giọng Turbo từ file"** của `VieNeuTurboLabView` (1.3.893) — chỉ để thử lõi nhân bản giọng Turbo, không
/// phải màn tạo giọng cho người dùng cuối (màn đó làm sau theo mockup). Logic ở `VieNeuTurboCloneTrial`.
extension VieNeuTurboLabView {
    @ViewBuilder
    var cloneSection: some View {
        let trial = lab.cloneTrial
        Section {
            VieNeuTurboClonePackRow { trial.refreshReadiness() }

            Button {
                trial.isPickingFile = true
            } label: {
                Label(trial.sampleURL?.lastPathComponent ?? "Chọn file âm thanh…", systemImage: "waveform")
            }
            .disabled(trial.isRunning)
            // `DocumentPickerPresenter` thay `.fileImporter` (bản SwiftUI không trả kết quả khi chạy trong
            // LiveContainer — xem `VieNeuVoiceCreatorView`); `asCopy` ⇒ URL đã nằm trong thư mục tạm của app.
            .background(
                DocumentPickerPresenter(
                    isPresented: Bindable(trial).isPickingFile,
                    allowedContentTypes: [.audio],
                    allowsMultipleSelection: false,
                    onPick: { urls in
                        if let url = urls.first { trial.acceptPickedFile(url) }
                    },
                    onCancel: nil
                )
            )

            TextField("Tên giọng", text: Bindable(trial).name)
                .disabled(trial.isRunning)
            Toggle("Khử nhiễu mẫu", isOn: Bindable(trial).denoise)
                .disabled(trial.isRunning)

            if let readiness = trial.readinessMessage {
                Text(readiness)
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
            }
            if trial.isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(Self.cloneStageText(trial.coordinator.stage))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                trial.run(lab: lab)
            } label: {
                Label("Tạo giọng Turbo", systemImage: "person.wave.2")
            }
            .buttonStyle(.appFilled)
            .disabled(!trial.canRun(labIsBusy: lab.isBusy))

            if !trial.statusMessage.isEmpty {
                Text(trial.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(trial.isError ? Color.red : Color.secondary)
            }
            if trial.createdVoiceId != nil {
                Button {
                    trial.readWithCreatedVoice(lab: lab)
                } label: {
                    Label("Đọc thử câu mẫu bằng giọng này", systemImage: "play.fill")
                }
                .disabled(!lab.isTurboReady || lab.isBusy)
            }
        } header: {
            SectionHelpHeader("Tạo giọng Turbo từ file", paragraphs: [
                "**Thử nghiệm lõi nhân bản giọng.** Các bước như bản gốc VieNeu Turbo: trộn mono → cắt khoảng lặng hai đầu (như `librosa.effects.trim`, 30 dB) → giữ tối đa 8 giây → khử nhiễu (`denoiser.onnx`, ra 44,1 kHz) → speaker embedding (`speaker_encoder.onnx`) → mã tham chiếu bằng audio.cpp.",
                "Báo thời gian từng bước, số khung (80 ms mỗi khung, tối đa 100) và RAM trước / sau. Giọng tạo xong có trong danh sách \"Giọng\" ở trên (mục \"Giọng tự tạo\"); bấm \"Đọc thử câu mẫu\" để nghe ngay.",
                "Chia sẻ `ref_codes.txt`, `speaker.emb.txt` và hai file WAV trung gian để so với script Python chạy bản gốc trên máy tính."
            ])
        }
        if !trial.report.isEmpty {
            cloneReportSection
        }
    }

    @ViewBuilder
    private var cloneReportSection: some View {
        let trial = lab.cloneTrial
        Section {
            Text(trial.report)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            ShareLink(
                item: VieNeuTurboReportFile(kind: .clone, engineName: "turbo"),
                preview: SharePreview("Số đo tạo giọng")
            ) {
                Label("Chia sẻ file số đo (.txt)", systemImage: "doc.text")
            }
            if let files = trial.createdVoiceFiles {
                ShareLink(item: files.referenceCodes) {
                    Label("Chia sẻ ref_codes.txt", systemImage: "square.and.arrow.up")
                }
                ShareLink(item: files.speakerEmbedding) {
                    Label("Chia sẻ speaker.emb.txt", systemImage: "square.and.arrow.up")
                }
            }
            if let url = trial.trimmedAudioURL {
                ShareLink(item: url) {
                    Label("Chia sẻ WAV sau cắt (trước khử nhiễu)", systemImage: "waveform")
                }
            }
            if let url = trial.processedAudioURL {
                ShareLink(item: url) {
                    Label("Chia sẻ WAV đưa vào audio.cpp", systemImage: "waveform")
                }
            }
        } header: {
            Text("Số đo tạo giọng")
        }
    }

    static func cloneStageText(_ stage: VieNeuTurboVoiceCloneCoordinator.Stage?) -> String {
        switch stage {
        case .decoding: return "Đang đọc file âm thanh…"
        case .trimming: return "Đang cắt khoảng lặng…"
        case .loadingGraphs: return "Đang nạp speaker_encoder / denoiser…"
        case .denoising: return "Đang khử nhiễu…"
        case .embedding: return "Đang tính speaker embedding…"
        case .encoding: return "Đang mã hoá giọng bằng audio.cpp…"
        case .saving: return "Đang lưu giọng…"
        case nil: return "Đang chuẩn bị…"
        }
    }
}
