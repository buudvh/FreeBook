import SwiftUI

/// Khối Model / Giọng & luồng / Đọc thử của `VieNeuTurboLabView`. Tách file vì trần 400 dòng; `@State lab` của view
/// dùng được vì đây là extension cùng type.
extension VieNeuTurboLabView {
    @ViewBuilder
    var modelSection: some View {
        Section {
            if !VieNeuTurboRuntime.isAvailable {
                Text("Bản build này chưa có audio.cpp (AudioCpp.xcframework) — tải model được nhưng chưa chạy được.")
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }
            if lab.store == nil {
                Text("Không dựng được thư mục model Turbo (Application Support không ghi được).")
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }
            LabeledContent("Trạng thái", value: modelStatusText)
            LabeledContent("Dung lượng", value: Self.formattedBytes(lab.bytesOnDisk))
            LabeledContent(
                "Bộ phiên âm",
                value: lab.hasG2PDictionary ? "sea_g2p.bin (chung với Nano)" : "Chưa có — tải kèm (~63 MB)"
            )
            LabeledContent("Thư viện", value: VieNeuTurboRuntime.versionDescription)
            LabeledContent("Nhiệt hiện tại", value: VieNeuTurboSoakStats.thermalName(lab.thermalState))

            if lab.isDownloading {
                VStack(alignment: .leading, spacing: 6) {
                    Text(lab.downloadMessage)
                        .font(.caption)
                    if let fraction = lab.downloadFraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                    }
                }
            } else if !lab.isTurboReady {
                Button {
                    lab.downloadAll()
                } label: {
                    Label("Tải model Turbo (~188 MB)", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.appFilled)
                .disabled(lab.store == nil)
            } else {
                Button(role: .destructive) {
                    lab.deleteModel()
                } label: {
                    Label("Xoá model Turbo", systemImage: "trash")
                }
                .disabled(lab.isBusy)
            }
        } header: {
            SectionHelpHeader("Model Turbo", paragraphs: [
                "**Thử nghiệm.** VieNeu-TTS v3 Turbo bản GGUF q8_0 chính thức (HuggingFace `pnnbao-ump/VieNeu-TTS-v3-Turbo`, ghim revision), chạy bằng thư viện **audio.cpp** (ggml) trên CPU — không phải ONNX như Nano.",
                "Model ra tiếng **stereo 48 kHz**; màn này trộn về mono rồi phát. Chữ đi qua cùng lớp đọc số / tiếng Nhật và cùng bộ phiên âm `sea_g2p.bin` với Nano, nên hai engine đọc cùng một chuỗi âm vị.",
                "Xoá model Turbo **không** xoá `sea_g2p.bin` — Nano vẫn cần nó."
            ])
        }
    }

    var modelStatusText: String {
        if lab.isTurboReady { return "Sẵn sàng · \(lab.voices.count) giọng" }
        var missing: [String] = []
        if !lab.hasModel { missing.append("model GGUF") }
        if !lab.hasG2PDictionary { missing.append("bộ phiên âm") }
        if lab.voices.isEmpty { missing.append("danh sách giọng") }
        return "Còn thiếu: " + missing.joined(separator: ", ")
    }

    @ViewBuilder
    var voiceSection: some View {
        Section {
            if lab.voices.isEmpty {
                Text("Tải model trước để có danh sách giọng.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Giọng", selection: $lab.selectedVoiceId) {
                    ForEach(lab.voices) { voice in
                        Text(voice.displayName).tag(voice.id)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Số luồng CPU")
                    .font(.subheadline)
                Picker("Số luồng CPU", selection: $lab.threadCount) {
                    ForEach(VieNeuTurboLab.threadChoices, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        } header: {
            SectionHelpHeader("Giọng & luồng", paragraphs: [
                "Mỗi giọng là hai file chữ nhỏ (mã tham chiếu + speaker embedding), tải ở lần dùng đầu.",
                "Số luồng của ggml (mặc định 2). Đổi số luồng chỉ dựng lại session, không nạp lại model. Nhiều luồng thường nhanh hơn nhưng nóng hơn — chính là thứ cần đo."
            ])
        }
        .disabled(lab.isBusy)
    }

    @ViewBuilder
    var sampleSection: some View {
        Section {
            TextEditor(text: $lab.text)
                .frame(minHeight: 110)
                .font(.body)
                .disabled(lab.isBusy)
            if lab.isWorking && !lab.isPreparingSoak {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(lab.workingMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if (lab.isWorking && !lab.isPreparingSoak) || lab.hasSamplePlayer {
                Button {
                    lab.stopSample()
                } label: {
                    Label("Dừng", systemImage: "stop.fill")
                }
                .buttonStyle(.appFilled(.red))
            } else {
                Button {
                    lab.readSampleOnce()
                } label: {
                    Label("Đọc thử một lần", systemImage: "play.fill")
                }
                .buttonStyle(.appFilled)
                .disabled(!lab.canRunTurbo)
            }
        } header: {
            SectionHelpHeader("Đọc thử", paragraphs: [
                "Tổng hợp **cả đoạn** trong một lượt (audio.cpp tự cắt chunk và chèn khoảng nghỉ), phát, rồi báo: thời gian nạp model (lần đầu), thời gian tổng hợp, độ dài tiếng, RTF, **CPU-s trên mỗi giây tiếng** và trạng thái nhiệt.",
                "Bấm đọc sẽ dừng TTS đang đọc truyện (hai bên dùng chung phiên âm thanh)."
            ])
        }
    }

    @ViewBuilder
    var sampleReportSection: some View {
        Section {
            Text(lab.lastReport)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let url = lab.lastAudioURL {
                ShareLink(item: url) {
                    Label("Chia sẻ audio", systemImage: "square.and.arrow.up")
                }
            }
            ShareLink(
                item: VieNeuTurboReportFile(kind: .sample, engineName: "turbo"),
                preview: SharePreview("Số đo đọc thử")
            ) {
                Label("Chia sẻ file số đo (.txt)", systemImage: "doc.text")
            }
        } header: {
            Text("Số đo đọc thử")
        }
    }
}
