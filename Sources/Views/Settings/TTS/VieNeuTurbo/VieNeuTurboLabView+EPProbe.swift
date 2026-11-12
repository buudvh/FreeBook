import SwiftUI

/// Khối **"So EP cho Nano (P1)"** của `VieNeuTurboLabView` — phép thử đúng / sai Core ML / Neural Engine / XNNPACK cho
/// VieNeu Nano trên máy. Logic ở `VieNeuNanoEPProbe` (`Services/TTS/VieNeu/Probe/`); màn chỉ vẽ.
extension VieNeuTurboLabView {
    @ViewBuilder
    var epProbeSection: some View {
        let probe = lab.epProbe
        Section {
            LabeledContent("Gói graph tĩnh") {
                Text(epPackageStatus(probe))
                    .foregroundStyle(.secondary)
            }
            if probe.isDownloading {
                if let fraction = probe.downloadFraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
                Text(probe.downloadMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !probe.isPackageReady {
                Button {
                    probe.download()
                } label: {
                    Label("Tải gói (~420 MB)", systemImage: "arrow.down.circle")
                }
                .disabled(lab.isBusy || probe.package == nil)
            }

            if probe.isRunning {
                Button {
                    probe.stop()
                } label: {
                    Label("Dừng So EP", systemImage: "stop.fill")
                }
                .buttonStyle(.appFilled(.red))
            } else {
                Button {
                    lab.startEPProbe()
                } label: {
                    Label("Chạy So EP", systemImage: "cpu")
                }
                .buttonStyle(.appFilled)
                .disabled(!probe.canRun || lab.isBusy)
            }

            if !probe.statusLine.isEmpty {
                Text(probe.statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = probe.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }
            ForEach(probe.summaryLines, id: \.self) { line in
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            if probe.hasReport {
                ShareLink(
                    item: VieNeuTurboReportFile(kind: .epProbe, engineName: "nano"),
                    preview: SharePreview("Kết quả So EP")
                ) {
                    Label("Chia sẻ file kết quả (.txt)", systemImage: "square.and.arrow.up")
                }
            }
            if !probe.wavURLs.isEmpty {
                ShareLink(items: probe.wavURLs) {
                    Label("Chia sẻ WAV để nghe (\(probe.wavURLs.count) file)", systemImage: "waveform")
                }
            }
            if probe.packageBytes > 0, !probe.isRunning, !probe.isDownloading {
                Button(role: .destructive) {
                    probe.deletePackage()
                } label: {
                    Label("Xoá gói + kết quả", systemImage: "trash")
                }
            }
        } header: {
            SectionHelpHeader("So EP cho Nano (P1)", paragraphs: [
                "Chạy 5 đoạn mẫu (quỹ đạo 8 bước + CFG 3) của Nano qua: **ORT CPU** (tham chiếu trên máy), **Core ML CPU-only** (fp32), **Core ML + GPU**, **Core ML + Neural Engine** và **XNNPACK**. Mỗi cấu hình ghi ms / CPU-ms mỗi lượt, độ lệch (SNR) so với ORT CPU, số NaN; cuối cùng đo Accelerate (kiểm AMX).",
                "Core ML CPU-only ra nhiễu như tháng 10 thì **tự bỏ qua** GPU + Neural Engine. Core ML phải biên dịch mỗi graph nên chạy lâu; **giữ màn này mở, đừng khoá máy** (màn hình không tự tắt trong lúc chạy; khoá máy là app bị treo vì không phát gì).",
                "Đường đọc truyện **không đổi**. Gói ~420 MB tải từ kho HF raikiri1498/VieNeu-TTS (thư mục nano-static), chỉ dùng cho phép thử; khi chạy, Core ML cần thêm chỗ trống tạm (vài trăm MB, tự xoá). Nút Xoá dọn gói, WAV và log."
            ])
        }
        .onChange(of: probe.isRunning) { _, running in
            UIApplication.shared.isIdleTimerDisabled = running
        }
    }

    private func epPackageStatus(_ probe: VieNeuNanoEPProbe) -> String {
        if probe.package == nil { return "Không dựng được thư mục" }
        if probe.isPackageReady { return "Đã tải · \(Self.formattedBytes(probe.packageBytes))" }
        if probe.packageBytes > 0 { return "Chưa đủ · \(Self.formattedBytes(probe.packageBytes))" }
        return "Chưa tải"
    }
}
