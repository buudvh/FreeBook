import SwiftUI

/// **Tạm thời** (1.3.1026) — màn **Thử nhịp dọc header** (Cài đặt › Ghi log hệ thống › Chẩn Đoán). Anh Bửu chọn mốc B
/// (nội dung đầu tiên cách đáy thanh / đáy ô tìm 16pt) rồi duyệt bản đo: một nút "Chạy" tự đẩy lần lượt các trang mẫu
/// (`HeaderSpacingLabVariant.all`), đo khoảng cách thật trên máy, hiện bảng kết quả + ghi log `📐 [HeaderLab]`, nút chia sẻ
/// gửi báo cáo. Theo cách anh dặn khi cần đo trên máy: một nút chạy hết, xong việc thì **xoá màn này** (cả thư mục
/// `HeaderSpacingLab/` và hàng mở nó ở `LogSettingsView`).
struct HeaderSpacingLabView: View {
    private struct ShareText: Identifiable {
        let text: String
        var id: String { text }
    }

    @State private var recorder = HeaderSpacingLabRecorder()
    @State private var shareText: ShareText?

    var body: some View {
        List {
            Section {
                Button {
                    recorder.start()
                } label: {
                    Label(recorder.isRunning ? "Đang chạy…" : "Chạy", systemImage: "play.circle")
                }
                .disabled(recorder.isRunning)
                if !recorder.progress.isEmpty {
                    Text(recorder.progress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                SectionHelpHeader("Tự thử", paragraphs: [
                    "Bấm Chạy rồi để yên khoảng 50 giây: app tự mở lần lượt \(HeaderSpacingLabVariant.all.count) trang mẫu và đo khoảng cách từ đáy thanh tiêu đề (hoặc đáy ô tìm) tới nội dung đầu tiên. Xong bấm nút chia sẻ góc phải gửi báo cáo cho Javis."
                ])
            }
            if !recorder.results.isEmpty {
                Section("Kết quả") {
                    ForEach(recorder.results) { result in
                        Text(result.text)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .backPageTitle("Thử nhịp dọc header")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareText = ShareText(text: recorder.reportText)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: HeaderMetrics.iconFontSize, weight: .semibold))
                        .frame(width: HeaderMetrics.iconFrameWidth, height: HeaderMetrics.iconFrameHeight, alignment: .trailing)
                }
                .disabled(recorder.results.isEmpty || recorder.isRunning)
                .accessibilityLabel("Chia sẻ báo cáo")
            }
        }
        .navigationDestination(item: $recorder.current) { variant in
            HeaderSpacingLabPage(variant: variant, recorder: recorder)
        }
        .sheet(item: $shareText) { item in
            ShareSheet(activityItems: [item.text])
        }
    }
}
