import SwiftUI

/// Mục **"Tăng tốc Core ML (thử nghiệm)"** của màn Cài đặt VieNeu TTS (P2c) — công tắc + tải / chuẩn bị một lần cho trình
/// đọc Nano. Logic ở `VieNeuCoreMLAccelerator` / `VieNeuCoreMLReaderRoute` (`Services/TTS/VieNeu/CoreML/`); màn chỉ vẽ.
extension VieNeuTTSTestView {
    @ViewBuilder
    var coreMLSection: some View {
        let accelerator = VieNeuCoreMLAccelerator.shared
        Section {
            Toggle("Tăng tốc Core ML", isOn: Binding(
                get: { accelerator.isEnabled },
                set: { accelerator.setEnabled($0) }
            ))
            .disabled(!isModelReady || accelerator.isBusy)

            if accelerator.isEnabled {
                LabeledContent("Trạng thái") {
                    Text(coreMLStateText(accelerator))
                        .foregroundStyle(.secondary)
                }
                if accelerator.isBusy {
                    if let fraction = accelerator.downloadFraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                    }
                    Button {
                        accelerator.cancel()
                    } label: {
                        Label("Dừng", systemImage: "stop.fill")
                    }
                } else if !accelerator.isVerified {
                    Button {
                        accelerator.prepare()
                    } label: {
                        Label(accelerator.isPackageComplete ? "Chuẩn bị (biên dịch + tự kiểm)" : "Tải & chuẩn bị (~267 MB)",
                              systemImage: "arrow.down.circle")
                    }
                    .disabled(!isModelReady || isBlockedByPlayback)
                }
            }
            if !accelerator.statusLine.isEmpty {
                Text(accelerator.statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = accelerator.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }
            if !accelerator.isBusy, accelerator.packageBytes + accelerator.cacheBytes > 0 {
                Button(role: .destructive) {
                    accelerator.deleteData()
                } label: {
                    Label("Xoá gói + bản biên dịch Core ML", systemImage: "trash")
                }
            }
        } header: {
            SectionHelpHeader("Tăng tốc Core ML (thử nghiệm)", paragraphs: [
                "Trình đọc Nano chạy phần nặng nhất (vòng tạo tiếng + codec) bằng **Core ML** của Apple trên CPU thay cho ONNX Runtime. Đo trên iPhone 11: nhanh ~2×, tốn CPU ít ~2,8×, máy mát hơn hẳn. Chất lượng **y hệt** (vẫn fp32, 8 bước, CFG).",
                "Lần đầu: tải gói ~267 MB (nên dùng Wi-Fi), biên dịch ~20 giây rồi **tự kiểm chất lượng** — qua kiểm mới dùng. Gói + bản biên dịch chiếm khoảng 1,2 GB thật trên ổ (con số ở dòng Trạng thái đếm cả phần hai bản dùng chung một vùng đĩa nên lớn hơn).",
                "Mỗi lần mở app, Core ML nạp sẵn trong vài giây. Đoạn quá dài, giọng khác dạng, hoặc Core ML lỗi thì đoạn đó tự đọc bằng cách cũ — không mất tiếng. Chỉ áp cho model Nano."
            ])
        }
        .onAppear { accelerator.refresh() }
    }

    private func coreMLStateText(_ accelerator: VieNeuCoreMLAccelerator) -> String {
        switch accelerator.phase {
        case .downloading: return "Đang tải gói…"
        case .preparing: return "Đang chuẩn bị…"
        case .idle:
            if accelerator.isVerified {
                return "Sẵn sàng · \(formattedBytes(accelerator.packageBytes + accelerator.cacheBytes))"
            }
            return accelerator.isPackageComplete ? "Cần chuẩn bị" : "Chưa tải"
        }
    }
}
