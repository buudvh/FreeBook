import SwiftUI

/// Màn quản lý model **VieNeu-TTS v3 Nano** — gom toàn bộ: bật/tắt **Core ML** (thử nghiệm), 8 gói Core
/// ML, tự test, và tải/xoá model **ONNX** (nền luôn trú). Tách khỏi `VieNeuTTSTestView` theo quyết định
/// grill #3 (2026-10-02): toggle + 8 gói + tự test nằm hết ở đây, Section 3 Cài đặt TTS chỉ là link.
///
/// **Không có hai nguồn sự thật**: model ONNX trước đây quản lý ở `VieNeuTTSTestView.modelSection`, nay
/// chuyển sang đây (plan §5.4 / §5.7). Mọi ghi model đều qua service/store, không đụng SwiftData.
struct VieNeuModelManagerView: View {
    @State var isDownloading = false
    @State var downloadProgress: Double = 0
    @State var downloadMessage = ""
    @State var statusMessage = ""
    @State var isError = false

    var service: VieNeuTTSService? { VieNeuTTSService.shared }
    var store: VieNeuModelStore? { service?.modelStore }

    var body: some View {
        // Poll trạng thái đĩa mỗi giây để hiện tiến độ tải/biên dịch Core ML mà không cần callback từ
        // service (service chạy nền, chỉ log). Một settings screen chịu 1 Hz disk-check là vô nghĩa.
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            Form {
                coreMLSection
                onnxSection
                if !statusMessage.isEmpty {
                    Section("Kết quả") {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(isError ? Color.red : Color.secondary)
                    }
                }
            }
            .tint(.white)
            .navigationTitle("Model VieNeu")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Hành động

    /// Tải model ONNX (4 graph + config + 2 asset, ~343 MB) — nền luôn trú và là fallback của Core ML.
    /// Chuyển từ `VieNeuTTSTestView.download()` (plan §5.7).
    func downloadModel() {
        guard let service else { return }
        isDownloading = true
        isError = false
        statusMessage = ""
        let client = VieNeuModelClient(store: service.modelStore)
        Task {
            do {
                _ = try await client.prefetch { message, fraction in
                    Task { @MainActor in
                        downloadMessage = message
                        downloadProgress = fraction
                    }
                }
                await MainActor.run {
                    isDownloading = false
                    statusMessage = "Tải xong model ONNX."
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    isError = true
                    statusMessage = "Tải ONNX thất bại: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Xoá model ONNX (không đụng Core ML, không đụng giọng user). Chuyển từ `VieNeuTTSTestView.deleteModel()`.
    func deleteModel() {
        guard let service else { return }
        do {
            try service.modelStore.deleteAll()
            statusMessage = "Đã xoá model ONNX."
            isError = false
        } catch {
            isError = true
            statusMessage = "Xoá ONNX thất bại: \(error.localizedDescription)"
        }
    }
}
