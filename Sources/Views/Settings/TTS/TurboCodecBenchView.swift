import SwiftUI

/// **TẠM — màn đo "Codec Turbo: AMX vs Neural Engine"** (hướng 3 báo cáo tối ưu Turbo §18, 1.3.932; anh Bửu duyệt
/// 2026-11-14). Một nút chạy `TurboCodecBenchRunner` rồi hiện + chia sẻ báo cáo. Mở từ mục Turbo của Cài đặt VieNeu TTS.
/// **Xoá màn này** (cùng `Services/TTS/VieNeuTurbo/CodecBench/`, dòng trong bridging header, hàng ở
/// `VieNeuTTSSettingsView+Sections`, `Caches/turbo-codec-bench/`) khi có kết luận.
struct TurboCodecBenchView: View {
    @State private var model = BenchModel()
    @State private var showingShare = false

    var body: some View {
        List {
            Section {
                Button {
                    model.start()
                } label: {
                    HStack(spacing: 10) {
                        if model.isRunning { ProgressView() }
                        Text(model.isRunning ? "Đang đo…" : "Chạy đo (khoảng 3–5 phút)")
                    }
                }
                .disabled(model.isRunning)
                if !model.status.isEmpty {
                    Text(model.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = model.errorText {
                    Text(error).foregroundStyle(.red)
                }
            } header: {
                SectionHelpHeader("Đo codec", paragraphs: [
                    "So phần giải mã ra tiếng (codec) của Turbo: **AMX** (đang dùng) với bản ONNX chính thức chạy **ORT CPU**, **Core ML CPU** và **Core ML + Neural Engine** — trên cùng mã âm thanh.",
                    "Lần đầu tải thêm khoảng **45 MB** và biên dịch Core ML (có thể mất vài chục giây). Giữ màn hình mở, đừng đọc truyện trong lúc đo. Xong thì bấm **Chia sẻ báo cáo** gửi Javis.",
                    "Màn này tạm thời — có kết luận thì gỡ."
                ])
            }
            if let report = model.reportText {
                Section("Báo cáo") {
                    Button("Chia sẻ báo cáo") { showingShare = true }
                    Text(report)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .backPageTitle("Đo codec Turbo")
        .sheet(isPresented: $showingShare) {
            if let url = model.reportURL {
                ShareSheet(activityItems: [url])
            }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    /// Trạng thái của lượt đo (lồng trong màn — một type chính mỗi file).
    @MainActor
    @Observable
    final class BenchModel {
        var isRunning = false
        var status = ""
        var errorText: String?
        var reportText: String?
        var reportURL: URL?

        func start() {
            guard !isRunning else { return }
            isRunning = true
            errorText = nil
            reportText = nil
            status = "Bắt đầu…"
            UIApplication.shared.isIdleTimerDisabled = true
            Task { @MainActor in
                do {
                    let (text, url) = try await TurboCodecBenchRunner().run { [weak self] message in
                        Task { @MainActor in self?.status = message }
                    }
                    reportText = text
                    reportURL = url
                    status = "Xong — bấm Chia sẻ báo cáo"
                    AppLogger.shared.log("🧪 [TurboCodecBench] Xong, báo cáo \(url.lastPathComponent)")
                } catch {
                    errorText = error.localizedDescription
                    status = ""
                    AppLogger.shared.log("❌ [TurboCodecBench] Lỗi: \(error.localizedDescription)")
                }
                isRunning = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }
}
