import SwiftUI

/// Màn **thử VieNeu Turbo (GGUF qua audio.cpp)** — bước thử nghiệm, mở từ màn "Cài đặt VieNeu TTS".
///
/// Câu hỏi màn này trả lời: Turbo q8_0 chạy bằng ggml trên CPU có **mát hơn** Nano (ONNX) không, và có đọc kịp không.
/// Vì vậy ngoài đọc thử một đoạn (RTF, CPU-s mỗi giây tiếng), có chế độ **đọc liên tục** nhiều phút để xem nhiệt — chạy
/// được cả Nano trên cùng văn bản để so cùng máy, cùng điều kiện.
///
/// Mọi logic (tải file, chạy model, phát) nằm ở `VieNeuTurboLab` (`Services/TTS/VieNeuTurbo/`); màn chỉ vẽ. Rời màn thì
/// dừng hết và nhả model; khoá màn hình thì vẫn chạy (không có `onDisappear`).
struct VieNeuTurboLabView: View {
    @State var lab = VieNeuTurboLab.shared

    var body: some View {
        Form { Group {
            modelSection
            voiceSection
            sampleSection
            if !lab.statusMessage.isEmpty {
                Section("Kết quả") {
                    Text(lab.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(lab.isError ? Color.red : Color.secondary)
                }
            }
            if !lab.lastReport.isEmpty {
                sampleReportSection
            }
            soakSection
            if lab.soak.isRunning || !lab.soak.summaryText.isEmpty {
                soakResultSection
            }
            epProbeSection
        }.glassSheetRows() }
        .backPageTitle("Thử VieNeu Turbo")
        .onAppear { lab.refreshStatus() }
        .onDisappear {
            // Phép thử So EP tắt tự khoá màn khi chạy; rời màn giữa chừng thì `onChange` của mục đó không kịp chạy.
            UIApplication.shared.isIdleTimerDisabled = false
            lab.leaveScreen()
        }
    }

    static func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
