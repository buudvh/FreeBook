import SwiftUI

/// Khối **"Đo nạp Core ML (P2a)"** của `VieNeuTurboLabView` — đo vì sao nạp session Core ML lâu và bản biên dịch nặng.
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
            SectionHelpHeader("Đo nạp Core ML (P2a)", paragraphs: [
                "Đo vì sao mỗi lần nạp session Core ML mất ~20 s và bản biên dịch chiếm ~4 GB. Dùng luôn gói + bản biên dịch của \"Đo tự động\", không tải hay biên dịch thêm.",
                "Bốn bước: (1) dung lượng từng mục — phần gói ORT ghi ra và phần bản biên dịch; (2) băm file trọng số tìm bản trùng; (3) nạp VE và codec bucket nhỏ nhất bằng **Core ML gốc** và bằng **ORT + Core ML EP**, mỗi cách 2 lần; (4) thử **bỏ bản trọng số của gói** ở một bucket (đổi tên, nạp lại, tự kiểm, rồi trả file về).",
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
