import SwiftUI

/// Toggle bật/tắt **Core ML** (thử nghiệm) cho VieNeu-TTS, kèm trạng thái tải/biên dịch/tự test và nút xoá.
///
/// Tách khỏi `VieNeuModelManagerView+Sections.coreMLSection` (plan 1.3.494) để tái dùng ở hai nơi:
/// 1. `vieNeuReaderSection` (Cài đặt TTS · Section 3, chỉ hiện khi chọn engine `vieneu`) — yêu cầu
///    "mang toggle ra ngoài", đặt ở **đầu** section.
/// 2. `VieNeuModelManagerView.coreMLSection` — màn quản lý model (kèm `packageList` ở dưới).
///
/// **Không** bọc `Section` riêng: khi dùng trong Section 3 nó lồng vào section "Quản lý riêng của trình
/// đọc"; khi dùng trong model manager nó nằm trong `Section` của `coreMLSection`. Header/footer "Core ML"
/// do `coreMLSection` giữ.
struct VieNeuCoreMLToggle: View {
    var service: VieNeuTTSService? { VieNeuTTSService.shared }
    var store: VieNeuModelStore? { service?.modelStore }

    private var useCoreML: Bool { service?.useCoreML ?? false }
    private var coreMLReady: Bool { store?.coreMLReady ?? false }
    private var compiledCount: Int { store?.coreMLCompiledCount ?? 0 }
    private var coreMLTotalBytes: Int64 { store?.coreMLTotalBytes ?? 0 }
    private var selfTestPassed: Bool { VieNeuBackendSelfTest.isPassed() }
    private var snrDb: Double { UserDefaults.standard.double(forKey: VieNeuSynthesisPolicy.coreMLSelfTestSNRKey) }

    /// Binding cho toggle Core ML: bật ⇒ ghi khoá ngay (toggle giữ ON trong lúc tải) rồi chạy
    /// `enableCoreML()` nền; tắt ⇒ về ONNX. Toast thuộc tầng View (Services không được toast).
    private var coreMLBinding: Binding<Bool> {
        Binding(
            get: { service?.useCoreML ?? false },
            set: { newValue in
                if newValue {
                    // Ghi khoá + báo engine ngay để toggle giữ ON trong lúc tải/biên dịch.
                    service?.useCoreML = true
                    Task {
                        guard let service else { return }
                        let result = await service.enableCoreML()
                        await MainActor.run {
                            if result.passed {
                                // Ghi lại khoá để engine re-prepare với Core ML (gói đã sẵn sàng + tự test đạt).
                                service.useCoreML = true
                                ToastManager.shared.show(
                                    message: "Core ML đã sẵn sàng — tự test đạt \(result.detail) dB.",
                                    type: .success
                                )
                            } else {
                                service.useCoreML = false
                                ToastManager.shared.show(
                                    message: "Core ML không khả dụng: \(result.detail)",
                                    type: .error
                                )
                            }
                        }
                    }
                } else {
                    service?.useCoreML = false
                    ToastManager.shared.show(message: "Đã tắt Core ML, quay lại ONNX.", type: .success)
                }
            }
        )
    }

    /// Dòng trạng thái khi toggle bật nhưng Core ML chưa sẵn sàng (đang tải/biên dịch/tự test).
    private var coreMLPhaseMessage: String {
        if compiledCount == 0 { return "Đang tải 8 gói Core ML (~398 MB)…" }
        if compiledCount < 8 { return "Đang biên dịch \(compiledCount)/8…" }
        return "Đang tự test…"
    }

    var body: some View {
        Toggle("Dùng Core ML (thử nghiệm)", isOn: coreMLBinding)
        if !useCoreML {
            Text("Tắt — bật để tải 8 gói (~398 MB), biên dịch và tự test trên máy. Core ML nhanh hơn ONNX (~1,4×, chưa đo máy thật).")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !coreMLReady {
            ProgressView(value: Double(compiledCount), total: 8) {
                Text(coreMLPhaseMessage)
            }
            .progressViewStyle(.linear)
        } else {
            LabeledContent("Bộ máy hiện tại", value: "Core ML (fallback ORT)")
            LabeledContent("Tự test", value: selfTestPassed ? "Đạt · \(String(format: "%.0f", snrDb)) dB" : "Chưa đạt")
            LabeledContent("Gói", value: "\(compiledCount)/8 · \(formattedBytes(coreMLTotalBytes))")
        }
        if coreMLReady {
            Button(role: .destructive) {
                deleteCoreML()
            } label: {
                Label("Xoá 8 gói Core ML", systemImage: "trash")
            }
        }
    }

    /// Xoá 8 gói Core ML: xoá đĩa + xoá kết quả tự test + tắt Core ML (trả về ONNX).
    private func deleteCoreML() {
        guard let store else { return }
        do {
            try store.deleteCoreML()
            VieNeuBackendSelfTest.reset()
            service?.useCoreML = false
            ToastManager.shared.show(message: "Đã xoá Core ML, quay lại ONNX.", type: .success)
        } catch {
            ToastManager.shared.show(message: "Xoá Core ML thất bại: \(error.localizedDescription)", type: .error)
        }
    }

    func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
