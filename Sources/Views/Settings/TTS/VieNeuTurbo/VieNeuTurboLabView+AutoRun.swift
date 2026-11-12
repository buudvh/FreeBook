import SwiftUI

/// Khối **"Đo tự động ORT ↔ Core ML (P1b)"** của `VieNeuTurboLabView` — một nút cho cả lượt dài: chuẩn bị Core ML, chờ
/// mát, ba lượt đọc A-B-A, file báo cáo. Logic ở `VieNeuAutoThermalRun` (`Services/TTS/VieNeuTurbo/AutoRun/`).
extension VieNeuTurboLabView {
    @ViewBuilder
    var autoRunSection: some View {
        let run = lab.autoRun
        Section {
            LabeledContent("Cấu hình") {
                Text("\(VieNeuAutoThermalRun.voiceName) · tổng hợp 1,15 · phát 1,5×")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Gói Core ML") {
                Text(autoRunPackageStatus(run))
                    .foregroundStyle(.secondary)
            }
            if run.isActive {
                if let fraction = run.downloadFraction {
                    ProgressView(value: fraction)
                }
                Text(run.statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    run.stop()
                } label: {
                    Label("Dừng đo tự động", systemImage: "stop.fill")
                }
                .buttonStyle(.appFilled(.red))
            } else {
                Button {
                    run.start(lab: lab)
                } label: {
                    Label("Bắt đầu đo tự động", systemImage: "thermometer.medium")
                }
                .buttonStyle(.appFilled)
                .disabled(lab.isBusy || !lab.isNanoReady || run.package == nil)
                if !run.statusLine.isEmpty {
                    Text(run.statusLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let error = run.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }
            if let note = run.abruptNote {
                // App bị giết giữa lượt đo (thường do hết RAM) — dòng cuối của nhật ký cho biết chết ở bước nào.
                Text("⚠️ Lần đo trước dừng đột ngột ở:\n\(note)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.orange)
                    .textSelection(.enabled)
            }
            if run.hasTrail, let url = run.trailURL {
                Button {
                    shareItem = ShareItem(urls: [url])
                } label: {
                    Label("Chia sẻ nhật ký từng bước", systemImage: "list.bullet.rectangle")
                }
            }
            ForEach(run.summaryLines, id: \.self) { line in
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            if let url = run.savedReportURL {
                Button {
                    shareItem = ShareItem(urls: [url])
                } label: {
                    Label("Chia sẻ file báo cáo (.txt)", systemImage: "square.and.arrow.up")
                }
            }
            if !run.isActive, run.packageBytes + run.cacheBytes > 0 {
                Button(role: .destructive) {
                    run.deleteData()
                } label: {
                    Label("Xoá gói + bản biên dịch Core ML", systemImage: "trash")
                }
            }
        } header: {
            SectionHelpHeader("Đo tự động ORT ↔ Core ML (P1b)", paragraphs: [
                "Bấm một lần, máy tự làm hết: tải gói Core ML (~270 MB, lần đầu), **biên dịch** cho máy (vài phút, máy ấm lên — màn hình giữ sáng trong lúc này), tự kiểm tiếng, rồi chạy **3 lượt đọc liên tục**: Nano ORT → Nano Core ML → Nano ORT.",
                "Trước **mỗi** lượt chờ máy mát liền 10 phút. Mỗi lượt đọc cùng văn bản bằng giọng Mai Anh, tổng hợp 1,15, phát 1,5×, tới khi máy lên **nóng** thì đọc thêm 5 đoạn rồi dừng (tối đa 15 phút). Cả lượt có thể mất 1–2 tiếng.",
                "Sau bước biên dịch cứ **khoá máy, để yên, rút sạc** — app tự giữ chạy (phát tiếng lúc đọc, vòng lặng lúc chờ). Rời màn này vẫn chạy. Mở TTS / nhạc / phim khác giữa chừng thì lượt đo tự dừng.",
                "Xong (hoặc dừng giữa chừng) bấm \"Chia sẻ file báo cáo\" gửi cho Javis. Bản biên dịch Core ML chiếm khoảng 1 GB, xoá bằng nút Xoá."
            ])
        }
        .onChange(of: run.phase) { _, phase in
            // Giữ sáng màn lúc tải + biên dịch (Core ML biên dịch ở tiền cảnh); lúc đo thì cho tự khoá như nghe thật.
            UIApplication.shared.isIdleTimerDisabled = phase == .downloading || phase == .preparing
        }
    }

    private func autoRunPackageStatus(_ run: VieNeuAutoThermalRun) -> String {
        guard run.package != nil else { return "không dựng được thư mục" }
        if run.packageBytes == 0 { return "chưa tải (tự tải khi bắt đầu)" }
        return "gói \(Self.formattedBytes(run.packageBytes)) · biên dịch \(Self.formattedBytes(run.cacheBytes))"
    }
}
