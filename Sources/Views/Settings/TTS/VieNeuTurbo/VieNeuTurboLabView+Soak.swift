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
                "Chọn **Nano** để chạy engine hiện tại trên cùng văn bản, cùng máy — so CPU/tiếng và nhiệt của hai engine."
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
            return "Turbo dùng giọng và số luồng chọn ở trên."
        case .nano:
            let threads = VieNeuSynthesisPolicy.effectiveThreadCount(from: .standard)
            return "Nano dùng giọng mặc định, chế độ và số luồng ORT ở Cài đặt VieNeu (hiện \(threads) luồng); tốc độ tổng hợp ép 1× cho cùng điều kiện với Turbo."
        }
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
            Button {
                ClipboardCopier.copy(soakDiagnosticText)
            } label: {
                Label {
                    Text("Sao chép kết quả đọc liên tục")
                } icon: {
                    AppGlyph.copy.image(size: 17)
                }
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

    /// Một khối chữ để dán vào chat: engine + tổng kết + từng phút + từng đoạn.
    var soakDiagnosticText: String {
        var parts = [lab.soak.engineDescription, lab.soak.summaryText]
        if !lab.soak.minuteLines.isEmpty {
            parts.append("— Từng phút —")
            parts.append(contentsOf: lab.soak.minuteLines.reversed())
        }
        if !lab.soak.chunkLines.isEmpty {
            parts.append("— Từng đoạn —")
            parts.append(contentsOf: lab.soak.chunkLines.reversed())
        }
        return parts.joined(separator: "\n")
    }
}
