import SwiftUI

/// Khối **"Đo nạp Core ML"** của `VieNeuTurboLabView` — đo vì sao nạp session Core ML lâu và bản biên dịch nặng, và thử
/// bản tắt tối ưu đồ thị ORT (P2b-0).
/// Logic ở `VieNeuCoreMLLoadProbe` / `VieNeuCoreMLLoadWorker` (`Services/TTS/VieNeu/CoreML/`); màn chỉ vẽ.
extension VieNeuTurboLabView {
    @ViewBuilder
    var coreMLLoadSection: some View {
        let probe = lab.coreMLLoad
        Section {
            if probe.isRunning {
                Button {
                    probe.stop()
                } label: {
                    Label("Dừng đo nạp", systemImage: "stop.fill")
                }
                .buttonStyle(.appFilled(.red))
            } else {
                Button {
                    lab.startCoreMLLoadProbe()
                } label: {
                    Label("Đo nạp Core ML", systemImage: "stopwatch")
                }
                .buttonStyle(.appFilled)
                .disabled(!probe.canRun || lab.isBusy)
                if !probe.isReady {
                    Text("Chưa có bản biên dịch Core ML — chạy \"Đo tự động\" ở trên tới hết bước chuẩn bị trước.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
                Button {
                    shareReport(kind: .coreMLLoad, engineName: "nano")
                } label: {
                    Label("Chia sẻ file kết quả (.txt)", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            SectionHelpHeader("Đo nạp Core ML (P2b-0)", paragraphs: [
                "Lần đo trước tìm ra: nạp session Core ML mất ~20 s và bản biên dịch nặng ~4 GB vì trọng số bị ghi **thành chữ** trong chương trình model (do một bước tối ưu của ORT), không nằm trong file trọng số.",
                "Lượt này thử **tắt tối ưu đồ thị ORT** cho Core ML: đọc lướt chương trình hiện tại, biên dịch lại VE + codec bucket nhỏ nhất ở bản tắt tối ưu (thư mục riêng), so dung lượng, thời gian nạp, chất lượng và **tốc độ mỗi lượt** với bản hiện tại.",
                "Mất vài phút, máy ấm lên. **Giữ màn này mở** (màn hình không tự tắt trong lúc đo). Đường đọc truyện không đổi."
            ])
        }
        .onChange(of: probe.isRunning) { _, running in
            UIApplication.shared.isIdleTimerDisabled = running
        }
        .onChange(of: lab.autoRun.isActive) { _, active in
            // Đo tự động vừa biên dịch xong (hoặc vừa xoá gói) ⇒ nút đo nạp đổi trạng thái ngay, không chờ mở lại màn.
            if !active { probe.refresh() }
        }
    }
}
