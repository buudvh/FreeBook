import SwiftUI

/// Các khối `Form` của `VieNeuModelManagerView`.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo. Đây là **extension cùng file type** nên
/// `@State` của view vẫn dùng được; các thành viên dùng chéo file buộc phải hạ từ `private` xuống
/// `internal` (Swift giới hạn `private` theo file) — cùng khuôn với `SeaG2P+Phonemize` và
/// `VieNeuTTSEngine+Adaptive`.
extension VieNeuModelManagerView {
    // MARK: - Trạng thái đọc từ đĩa (poll qua TimelineView)

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

    // MARK: - Core ML

    @ViewBuilder
    var coreMLSection: some View {
        Section {
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
            packageList
        } header: {
            Text("Core ML (thử nghiệm)")
        } footer: {
            Text("Core ML chạy hoàn toàn trên máy. Khi một đoạn lỗi, engine tự rớt về ONNX cho riêng đoạn đó — không khựng, không im lặng. Tắt để quay lại ONNX.")
        }
    }

    /// 8 gói Core ML, xanh khi đã biên dịch `.mlmodelc`, xám khi chưa.
    @ViewBuilder
    var packageList: some View {
        ForEach(VieNeuModelStore.coreMLPackageNames, id: \.self) { name in
            let url = store?.coreMLCompiledURL(for: name)
            let ready = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            HStack(spacing: 8) {
                Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(ready ? Color.green : Color.secondary)
                Text(name)
                    .font(.footnote)
                Spacer()
            }
        }
    }

    // MARK: - ONNX (nền luôn trú)

    /// Quản lý model ONNX — chuyển từ `VieNeuTTSTestView.modelSection` (plan §5.7).
    @ViewBuilder
    var onnxSection: some View {
        Section {
            if let store, store.isReady {
                LabeledContent("Trạng thái", value: "Đã tải đủ 8 file")
                LabeledContent("Dung lượng", value: formattedBytes(store.totalBytes))
            } else {
                LabeledContent("Còn thiếu", value: "\(store?.missingNames.count ?? 0) file")
                Text("Cần tải khoảng 343 MB: 4 graph ONNX + config.json + constants.npz từ HuggingFace, voices_v3_nano.json và sea_g2p.bin từ GitHub. Cả ba nguồn đều ghim sha nên tác giả đổi file cũng không làm app hỏng.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isDownloading {
                ProgressView(value: downloadProgress) {
                    Text(downloadMessage)
                        .font(.caption)
                }
            } else if let store, store.isReady {
                Button(role: .destructive) {
                    deleteModel()
                } label: {
                    Label("Xoá model ONNX", systemImage: "trash")
                }
            } else {
                Button {
                    downloadModel()
                } label: {
                    Label("Tải model VieNeu (ONNX)", systemImage: "arrow.down.circle")
                }
                .disabled(service == nil)
            }
        } header: {
            Text("Model ONNX (mặc định)")
        } footer: {
            Text("Engine local luôn trú, làm nền và là fallback cho Core ML. Gói graph nhân bản giọng (~91 MB) tải riêng ở “Giọng của tôi”.")
        }
    }

    func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
