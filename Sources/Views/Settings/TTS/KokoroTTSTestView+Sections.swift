import SwiftUI
import UIKit

/// Các khối `Form` của `KokoroTTSTestView`.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo. Đây là **extension cùng file type** nên `@State`
/// của view vẫn dùng được; thành viên dùng chéo file buộc phải để mức `internal` (Swift giới hạn `private`
/// theo file) — cùng khuôn `VieNeuTTSTestView+Sections`.
extension KokoroTTSTestView {
    @ViewBuilder
    var modelSection: some View {
        Section {
            if engine == nil {
                Text("Không dựng được kho model Kokoro (thư mục Application Support không ghi được).")
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            } else if isModelReady {
                LabeledContent("Trạng thái", value: "Đã tải đủ")
                LabeledContent("Giọng", value: "\(voices.count)")
                LabeledContent("Dung lượng", value: byteText(store?.totalBytes ?? 0))
            } else {
                LabeledContent("Còn thiếu", value: "\(store?.missingNames.count ?? 0) file")
                Text("Cần khoảng **318 MB**: graph ONNX 310,6 MB + 14 voicepack 0,5 MB + `config.json` + `voices.json` từ HuggingFace. **Không** tải `kokoro_vi.pth` (312 MB — chỉ để export ONNX).")
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
                    Label("Tải model Kokoro", systemImage: "arrow.down.circle")
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
            Text("Engine local, chạy hoàn toàn trên máy. Kokoro dùng **chung `sea_g2p.bin` với VieNeu** (đã xác minh bằng mã băm là cùng một file), nên **cần model VieNeu có trên máy**. Nút “Xoá model” cố ý **không** xoá file đó — nó thuộc engine mặc định của bạn.")
        }
    }

    @ViewBuilder
    var voiceSection: some View {
        Section {
            if voices.isEmpty {
                Text(isModelReady ? "Chưa đọc được danh sách giọng." : "Tải model trước để có danh sách giọng.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Giọng", selection: $selectedVoiceKey) {
                    ForEach(voices) { voice in
                        Text(voice.label).tag(voice.key)
                    }
                }
            }
        } header: {
            Text("Giọng đọc")
        } footer: {
            Text("Mỗi giọng chỉ **0,5 MB** vì Kokoro dùng **một** graph chung cho cả 14 giọng — khác Piper (mỗi giọng là một model 60,6 MB).")
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
            Text("Chữ ở đây đi qua **đúng một** lớp tiền xử lý: `TTSReplacementManager.applyReplacements`. Cố ý **không** gọi `TextPreprocessor.normalizeVietnameseText` — Kokoro có vocab dấu câu và bộ G2P riêng đã xử lý số/ngày, mở rộng số thành chữ trước khi vào model là lệch khỏi bản tham chiếu.")
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
            Text("Chỉ đổi tốc độ **phát**, không đổi tốc độ **tạo**: audio luôn được tổng hợp ở 1,0× rồi phát nhanh/chậm hơn. Đổi là tức thì, không phải tổng hợp lại.")
        }
    }

    @ViewBuilder
    var synthesisSpeedSection: some View {
        Section {
            HStack {
                Text("0.5×").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $synthesisSpeed, in: 0.5...2.0, step: 0.05)
                    .tint(.white)
                Text("2.0×").font(.caption2).foregroundStyle(.secondary)
            }
            LabeledContent("Đang chọn", value: String(format: "%.2f× · đưa vào model", synthesisSpeed))
        } header: {
            Text("Tốc độ tạo audio")
        } footer: {
            Text("Đây là `speed` **đưa thẳng vào graph Kokoro** — khác VieNeu (vốn có vòng Euler nhiều bước để chọn). Đổi tốc độ là **phải tổng hợp lại**, và **số RTF chỉ so được khi để 1,00×** vì tốc độ khác làm đổi cả thời gian suy luận lẫn độ dài audio.")
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
                Text("Lượt đầu phải nạp graph 310 MB nên sẽ đứng vài giây; các lượt sau dùng lại. Nút Dừng ngắt **phát** và bỏ kết quả.")
            }
        }
    }

    /// Dung lượng dạng người đọc được. Tên khác `formattedBytes` của màn VieNeu để không đụng hàm cùng tên.
    func byteText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
