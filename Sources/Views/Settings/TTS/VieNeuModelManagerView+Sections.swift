import SwiftUI

/// Các khối `Form` của `VieNeuModelManagerView`.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo. Đây là **extension cùng file type** nên
/// `@State` của view vẫn dùng được; các thành viên dùng chéo file buộc phải hạ từ `private` xuống
/// `internal` (Swift giới hạn `private` theo file) — cùng khuôn với `SeaG2P+Phonemize` và
/// `VieNeuTTSEngine+Adaptive`.
extension VieNeuModelManagerView {
    // MARK: - Core ML

    /// Toggle + trạng thái Core ML — tái dùng `VieNeuCoreMLToggle` (plan 1.3.494). Component đã chứa
    /// toggle, dòng trạng thái (đang tải/biên dịch/tự test) và nút xoá 8 gói. Ở đây chỉ giữ `packageList`
    /// kèm header/footer "Core ML".
    @ViewBuilder
    var coreMLSection: some View {
        Section {
            VieNeuCoreMLToggle()
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
            let url = store?.compiledURL(for: name)
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
