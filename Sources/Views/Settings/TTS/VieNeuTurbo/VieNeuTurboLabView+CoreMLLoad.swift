import SwiftUI

/// Khối **"Đo nạp Core ML"** của `VieNeuTurboLabView` — P2b-1: tải gói định dạng 3 (trọng số không còn bị ghi thành chữ
/// trong model), biên dịch VE + codec bucket nhỏ nhất, đo dung lượng / thời gian nạp / chất lượng / tốc độ.
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
                    Text("Không dựng được thư mục gói Core ML.")
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
            SectionHelpHeader("Đo nạp Core ML (P2b-1)", paragraphs: [
                "Gói Core ML mới (định dạng 3) được xuất lại trên PC để trọng số nằm trong **file trọng số** thay vì bị ghi thành chữ trong chương trình model — nguyên nhân nạp ~20 s và bản biên dịch ~4 GB. Phép tính không đổi.",
                "Bấm một lần: tự **tải phần gói đã đổi** (~270 MB lần đầu, nên dùng Wi-Fi; bản biên dịch cũ tự xoá), biên dịch VE + codec bucket nhỏ nhất, rồi đo dung lượng, thời gian nạp, chất lượng (phải trùng số cũ) và **tốc độ mỗi lượt** (phải như cũ).",
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
