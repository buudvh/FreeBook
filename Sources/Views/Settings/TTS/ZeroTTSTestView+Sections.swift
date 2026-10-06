import SwiftUI
import UIKit

/// Các khối `Form` của `ZeroTTSTestView`.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo. Đây là **extension cùng file type** nên
/// `@State` của view vẫn dùng được; thành viên dùng chéo file buộc phải để mức `internal` (Swift giới hạn
/// `private` theo file) — cùng khuôn với `VieNeuTTSTestView+Sections`.
extension ZeroTTSTestView {
    @ViewBuilder
    var modelSection: some View {
        Section {
            if engine == nil {
                Text("Không dựng được kho model ZeroTTS (thư mục Application Support không ghi được).")
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            } else if isModelReady {
                LabeledContent("Trạng thái", value: "Đã tải đủ \(ZeroTTSModelStore.requiredFileNames.count) file")
                LabeledContent("Giọng", value: "\(store?.voiceNames.count ?? 0)")
                LabeledContent("Dung lượng", value: byteText(store?.totalBytes ?? 0))
            } else {
                LabeledContent("Còn thiếu", value: "\(store?.missingNames.count ?? 0) file")
                Text("Cần khoảng **903 MB**: ba graph ONNX (323 + 348 + 187 MB) + codec MOSS (~45 MB) + `config.json`, `tokenizer.json`, `voices/index.json` và 8 giọng preset — tải từ HuggingFace `zeroweight-ai/ZeroTTS`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isDownloading {
                ProgressView(value: downloadProgress) {
                    Text(downloadMessage)
                        .font(.caption)
                }
            } else if !isModelReady {
                Button {
                    download()
                } label: {
                    Label("Tải model ZeroTTS", systemImage: "arrow.down.circle")
                }
                .disabled(engine == nil)
            } else {
                Button(role: .destructive) {
                    deleteModel()
                } label: {
                    Label("Xoá model", systemImage: "trash")
                }
            }
        } header: {
            Text("Model")
        } footer: {
            Text("Engine local, chạy hoàn toàn trên máy — không có request nào ra ngoài ngoài lúc tải model. Graph là **fp32, không lượng tử hoá**: bản upstream đo được rằng int8 *chậm hơn* fp32 trên CPU, nên đừng kỳ vọng bản nhẹ hơn sẽ nhanh hơn.")
        }
    }

    @ViewBuilder
    var voiceSection: some View {
        // **Không** dùng `Section("Giọng đọc") { … } footer: { … }`: SwiftUI không có initializer
        // `Section(_:content:footer:)`, nên dạng đó là lỗi biên dịch (`missing argument label 'content:'`).
        // Muốn có cả tiêu đề lẫn footer thì phải `Section { } header: { } footer: { }`.
        Section {
            if voices.isEmpty {
                Text(isModelReady ? "Chưa đọc được danh sách giọng." : "Tải model trước để có danh sách giọng.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Giọng", selection: $selectedVoice) {
                    ForEach(voices) { voice in
                        Text(voice.displayName).tag(voice.name)
                    }
                }
            }
        } header: {
            Text("Giọng đọc")
        } footer: {
            if let voice = voices.first(where: { $0.name == selectedVoice }), !voice.summary.isEmpty {
                Text("**\(voice.displayName)** — \(voice.summary). Bản open-source **không** kèm voice encoder: nó chỉ *nạp* giọng, không *tạo* giọng từ audio, nên chỉ có tám giọng preset này.")
            }
        }
    }

    @ViewBuilder
    var textSection: some View {
        Section {
            TextEditor(text: $text)
                .frame(minHeight: 110)
                .font(.body)
            HStack(spacing: 28) {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .accessibilityLabel("Xoá hết chữ")
                .disabled(text.isEmpty)

                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Sao chép chữ")
                .disabled(text.isEmpty)

                Button {
                    if let pasted = UIPasteboard.general.string { text = pasted }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .accessibilityLabel("Dán chữ")
                .disabled(!UIPasteboard.general.hasStrings)

                // Phát / Dừng căn **sang phải**, tách khỏi nhóm xoá-sao chép-dán (cùng bố cục màn thử VieNeu).
                Spacer()

                Button {
                    playSample()
                } label: {
                    if isSynthesizing || isPreparing {
                        ProgressView()
                    } else {
                        Image(systemName: "play.circle.fill")
                    }
                }
                .accessibilityLabel("Phát thử")
                .disabled(!canPlay)

                Button {
                    stopPlayback()
                } label: {
                    Image(systemName: "play.slash")
                }
                .accessibilityLabel("Dừng")
                .disabled(player == nil && synthesisTask == nil)
            }
            // `.borderless` là bắt buộc: trong một hàng của `Form`, mặc định cả hàng là **một** nút nên mọi
            // cú chạm đều rơi vào nút đầu tiên.
            .buttonStyle(.borderless)
        } header: {
            Text("Chữ cần đọc")
        } footer: {
            Text("Chữ ở đây đi qua **đúng một** lớp tiền xử lý: `TTSReplacementManager.applyReplacements`. Cố ý **không** gọi `TextPreprocessor.normalizeVietnameseText` — ZeroTTS tự đọc số, ngày và viết tắt bằng chính model, nên mở rộng số thành chữ trước khi vào model là lệch khỏi bản tham chiếu.")
        }
    }

    @ViewBuilder
    var speedSection: some View {
        Section {
            HStack {
                Text("0.5×").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $speed, in: 0.5...2.0, step: 0.05)
                    .tint(.white)
                Text("2.0×").font(.caption2).foregroundStyle(.secondary)
            }
            LabeledContent("Đang chọn", value: String(format: "%.2f×", speed))
        } header: {
            Text("Tốc độ phát")
        } footer: {
            Text("Chỉ đổi tốc độ **phát**, không đổi tốc độ **tạo**: audio luôn được tổng hợp ở 1,0× rồi phát nhanh/chậm hơn. Nhờ vậy số RTF đo được luôn ứng với 1,0×.")
        }
    }

    /// Khối tham số lấy mẫu.
    ///
    /// Khác khối "Tốc độ tạo audio" của màn thử VieNeu: kiến trúc ZeroTTS **không** có vòng Euler nhiều
    /// bước (mỗi frame là **một** lượt `local_frame_decode`), nên thứ vặn được chỉ là tham số lấy mẫu —
    /// nhiệt độ, top-k, top-p, phạt lặp.
    @ViewBuilder
    var samplingSection: some View {
        Section {
            Picker("Chế độ", selection: $samplingMode) {
                ForEach(SamplingMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            LabeledContent("Nhiệt độ", value: String(format: "%.2f", samplingMode.sampling.audioTemperature))
            LabeledContent("Top-p", value: String(format: "%.2f", samplingMode.sampling.audioTopP))
            LabeledContent("Phạt lặp", value: String(format: "%.2f", samplingMode.sampling.audioRepetitionPenalty))
            LabeledContent("Trần frame", value: "\(samplingMode.sampling.maxFrames)")
        } header: {
            Text("Lấy mẫu")
        } footer: {
            Text("Mặc định là nguyên bộ `DEFAULT_SAMPLING` của upstream. `cfg_scale` bị **ghim ở 1,0**: classifier-free guidance cần batch 2 (`[voice ‖ null_voice]`) mà bản port này mới chạy batch 1. Trần frame hạ từ 1500 của upstream xuống 500 (40 giây) vì `packed_kv` được cấp trước theo trần đó — ở 1500 thì riêng KV đã ~83 MB.")
        }
    }

    @ViewBuilder
    var playSection: some View {
        Section {
            LabeledContent(
                "Trạng thái",
                value: isPreparing ? "Đang nạp engine…" : (isSynthesizing ? "Đang tổng hợp…" : "Sẵn sàng")
            )

            if let shareURL {
                ShareLink(item: shareURL) {
                    Label("Chia sẻ audio", systemImage: "square.and.arrow.up")
                }
            }
        } footer: {
            if isBlockedByPlayback {
                Text("Đang đọc truyện — hãy dừng TTS trước khi thử, vì hai bên dùng chung phiên âm thanh.")
            } else {
                Text("Lượt đầu phải nạp bốn graph (~903 MB) nên sẽ đứng vài giây; các lượt sau dùng lại. Nút Dừng ngắt **phát** và bỏ kết quả, nhưng không cắt ngang vòng sinh frame đang chạy — việc nặng chạy ở `Task.detached` nên huỷ không xuyên qua được.")
            }
        }
    }

    /// Dung lượng dạng người đọc được. Cố ý đặt tên khác `formattedBytes` của màn thử VieNeu để không
    /// đụng hàm cùng tên ở phạm vi file.
    func byteText(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
