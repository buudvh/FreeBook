import SwiftUI

/// Khối "Đọc liên tục (đo nhiệt)" + kết quả của nó trong `VieNeuTurboLabView`.
extension VieNeuTurboLabView {
    @ViewBuilder
    var soakSection: some View {
        Section {
            Picker("Engine", selection: $lab.soakEngine) {
                ForEach(VieNeuTurboLab.SoakEngine.allCases) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            .pickerStyle(.segmented)
            .disabled(lab.isBusy)

            Text(engineNote)
                .font(.caption)
                .foregroundStyle(.secondary)

            if lab.soakEngine == .nano {
                nanoTuningRows
            } else {
                // QoS cho lượt Turbo (1.3.854): userInitiated = lõi hiệu năng (trình đọc dùng mức này từ 1.3.856),
                // utility = lõi tiết kiệm để so.
                Picker("QoS", selection: $lab.turboQoS) {
                    ForEach(VieNeuTurboLab.SoakQoS.allCases) { qos in
                        Text(qos.rawValue).tag(qos)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(lab.isBusy)
            }

            TextEditor(text: $lab.longText)
                .frame(minHeight: 160)
                .font(.callout)
                .disabled(lab.isBusy)
            HStack {
                Text("\(lab.longText.count) ký tự")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Dùng văn bản mẫu") {
                    lab.longText = VieNeuTurboSampleText.long
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(lab.isBusy || lab.longText == VieNeuTurboSampleText.long)
            }

            if lab.soak.isRunning || lab.isPreparingSoak {
                Button {
                    lab.stopSoak()
                } label: {
                    Label("Dừng đọc liên tục", systemImage: "stop.fill")
                }
                .buttonStyle(.appFilled(.red))
            } else {
                Button {
                    lab.startSoak()
                } label: {
                    Label("Bắt đầu đọc liên tục", systemImage: "waveform")
                }
                .buttonStyle(.appFilled)
                .disabled(!lab.canStartSoak)
            }

            if lab.isPreparingSoak {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(lab.workingMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if !lab.soak.statusLine.isEmpty {
                Text(lab.soak.statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = lab.soak.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }
        } header: {
            SectionHelpHeader("Đọc liên tục (đo nhiệt)", paragraphs: [
                "Lặp văn bản dài, cắt **≤ 150 ký tự theo câu** bằng đúng bộ cắt Reader dùng, tổng hợp trước tối đa **2 đoạn** và phát nối tiếp. Khoá màn hình vẫn chạy; rời màn này là dừng.",
                "Mỗi đoạn và mỗi phút ghi: giây tiếng, CPU-s (cả tiến trình), **CPU/tiếng**, số lần **hụt tiếng** (trình phát phải chờ) và trạng thái nhiệt. Số liệu cũng vào log `[VieNeuTurbo]` (bật ghi log ở Cài đặt).",
                "Chọn **Nano** để chạy engine hiện tại trên cùng văn bản, cùng máy — so CPU/tiếng và nhiệt của hai engine. Nano còn ghi **phân rã** từng đoạn: vòng Euler / codec / text_encoder.",
                "**Số luồng** và **QoS** của Nano chỉ áp trong lúc đo, không đổi cài đặt; dừng hoặc rời màn là trả lại như cũ. QoS thấp hay chạy ở lõi tiết kiệm: chậm hơn nhưng có thể mát hơn — so diễn biến nhiệt, đừng so CPU-s giữa hai mức QoS.",
                "Nút **Chia sẻ file kết quả** gửi một file .txt đủ tổng kết, từng phút và mọi đoạn."
            ])
        } footer: {
            if let reason = soakBlockedReason {
                Text(reason)
            }
        }
    }

    var engineNote: String {
        switch lab.soakEngine {
        case .turbo:
            return "Turbo dùng giọng và số luồng chọn ở trên; QoS chọn dưới đây chỉ cho lượt đo (trình đọc chạy userInitiated). Nghe ở tốc độ X× cần RTF dưới 1/X, vd 1,4× cần dưới 0,71."
        case .nano:
            let threads = VieNeuSynthesisPolicy.effectiveThreadCount(from: .standard)
            return "Nano dùng giọng mặc định và chế độ ở Cài đặt VieNeu; số luồng + QoS chọn dưới đây chỉ cho lượt đo (cài đặt hiện \(threads) luồng, trình đọc chạy userInitiated). Tốc độ tổng hợp ép 1× cho cùng điều kiện với Turbo."
        }
    }

    /// Số luồng ORT + QoS cho lượt Nano (1.3.849) — đo A/B lõi hiệu năng / lõi tiết kiệm.
    @ViewBuilder
    var nanoTuningRows: some View {
        Picker("Số luồng ORT", selection: $lab.nanoThreadCount) {
            ForEach(VieNeuTurboLab.nanoThreadChoices, id: \.self) { count in
                Text("\(count) luồng").tag(count)
            }
        }
        .pickerStyle(.segmented)
        .disabled(lab.isBusy)
        Picker("QoS", selection: $lab.nanoQoS) {
            ForEach(VieNeuTurboLab.SoakQoS.allCases) { qos in
                Text(qos.rawValue).tag(qos)
            }
        }
        .pickerStyle(.segmented)
        .disabled(lab.isBusy)
    }

    /// Lý do không bấm được "Bắt đầu" — chỉ khi không bận (đang bận thì nút Dừng đã nói đủ).
    var soakBlockedReason: String? {
        guard !lab.isBusy, !lab.canStartSoak else { return nil }
        switch lab.soakEngine {
        case .turbo:
            if !VieNeuTurboRuntime.isAvailable { return "Bản build này chưa có audio.cpp." }
            return "Tải model Turbo trước."
        case .nano:
            return "Chưa tải model VieNeu Nano — tải ở màn Cài đặt VieNeu TTS."
        }
    }

    @ViewBuilder
    var soakResultSection: some View {
        Section {
            if !lab.soak.engineDescription.isEmpty {
                Text(lab.soak.engineDescription)
                    .font(.footnote.weight(.semibold))
            }
            Text(lab.soak.summaryText)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            ShareLink(
                // Tên theo engine của lượt vừa chạy, không theo ô chọn (đổi ô chọn sau khi dừng không đổi kết quả).
                item: VieNeuTurboReportFile(
                    kind: .soak,
                    engineName: lab.soak.engineDescription.hasPrefix("Nano") ? "nano" : "turbo"
                ),
                preview: SharePreview("Kết quả đọc liên tục")
            ) {
                Label("Chia sẻ file kết quả (.txt)", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Tổng kết đọc liên tục")
        }

        if !lab.soak.minuteLines.isEmpty {
            Section("Từng phút (mới nhất trên cùng)") {
                ForEach(lab.soak.minuteLines, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }

        if !lab.soak.chunkLines.isEmpty {
            Section("Từng đoạn (40 đoạn gần nhất)") {
                ForEach(lab.soak.chunkLines, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
