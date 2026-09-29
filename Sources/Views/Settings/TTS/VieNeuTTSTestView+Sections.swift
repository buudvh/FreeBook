import SwiftUI

/// Các khối `Form` của `VieNeuTTSTestView`.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo. Đây là **extension cùng file type** nên
/// `@State` của view vẫn dùng được; các thành viên dùng chéo file buộc phải hạ từ `private` xuống
/// `internal` (Swift giới hạn `private` theo file) — cùng khuôn với `SeaG2P+Phonemize` và
/// `VieNeuTTSEngine+Adaptive`.
extension VieNeuTTSTestView {
    @ViewBuilder
    var modelSection: some View {
        Section {
            if service == nil {
                Text("Không dựng được kho model VieNeu (thư mục Application Support không ghi được).")
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            } else if isModelReady {
                LabeledContent("Trạng thái", value: "Đã tải đủ 8 file")
                LabeledContent("Dung lượng", value: formattedBytes(store?.totalBytes ?? 0))
            } else {
                LabeledContent("Còn thiếu", value: "\(store?.missingNames.count ?? 0) file")
                Text("Cần tải khoảng 343 MB: 4 graph ONNX + `config.json` + `constants.npz` từ HuggingFace, `voices_v3_nano.json` và `sea_g2p.bin` từ GitHub. Cả ba nguồn đều **ghim sha** nên tác giả đổi file cũng không làm app hỏng.")
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
                    Label("Tải model VieNeu", systemImage: "arrow.down.circle")
                }
                .disabled(service == nil)
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
            Text("Engine local, chạy hoàn toàn trên máy. Giọng đọc không nằm trong file model mà là hai mảng số trong `voices_v3_nano.json`, nên 11 giọng dùng chung một bộ graph.")
        }
    }

    @ViewBuilder
    var voiceSection: some View {
        Section("Giọng đọc") {
            if voices.isEmpty {
                Text(isModelReady ? "Chưa đọc được danh sách giọng." : "Tải model trước để có danh sách giọng.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Giọng", selection: $selectedVoice) {
                    ForEach(voices) { voice in
                        Text(voice.name).tag(voice.name)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var textSection: some View {
        Section("Chữ cần đọc") {
            TextEditor(text: $text)
                .frame(minHeight: 110)
                .font(.body)
        }
    }

    @ViewBuilder
    var speedSection: some View {
        Section("Tốc độ") {
            HStack {
                Text("0.5×").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $speed, in: 0.5...2.0, step: 0.05)
                    .tint(.white)
                Text("2.0×").font(.caption2).foregroundStyle(.secondary)
            }
            LabeledContent("Đang chọn", value: String(format: "%.2f×", speed))
        }
    }

    /// Bộ chọn tốc độ tạo audio.
    ///
    /// Đây là **lựa chọn của người dùng**, không phải cơ chế thích nghi: bộ thích nghi chỉ hạ bước khi máy
    /// không theo kịp, còn ở đây người dùng chủ động đổi lấy tốc độ. Vì vậy khi có lựa chọn, engine **tắt
    /// hẳn** thích nghi — nếu không, nó sẽ tự nâng/hạ và ghi đè đúng thứ người dùng vừa đặt.
    @ViewBuilder
    var qualitySection: some View {
        Section {
            Picker("Chế độ", selection: modeSelection) {
                Text("Tự động (theo tốc độ máy)").tag(VieNeuSynthesisPolicy.Mode?.none)
                ForEach(VieNeuSynthesisPolicy.Mode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(VieNeuSynthesisPolicy.Mode?.some(mode))
                }
            }
            LabeledContent("Đang chạy", value: service?.currentMode.displayName ?? "—")
        } header: {
            Text("Tốc độ tạo audio")
        } footer: {
            Text("Mỗi bước là một lượt `vector_estimator`, và CFG chạy thêm **một lượt nữa cho mỗi bước** — nên 16 bước tốn 32 lượt cho mỗi đoạn. Giảm số bước là cách duy nhất vừa nhanh hơn vừa **mát máy hơn**; đổi lại chất lượng giọng giảm. Bản tham chiếu của model khuyến nghị cặp 8 bước + sway −1. Mục “Nhanh nhất” tắt CFG — model card cảnh báo thẳng là giảm độ rõ.")
        }
    }

    /// `nil` = tự động. Picker cần `Binding<Mode?>` nên gói thủ công.
    var modeSelection: Binding<VieNeuSynthesisPolicy.Mode?> {
        Binding(
            get: { service?.preferredMode },
            set: { service?.preferredMode = $0 }
        )
    }

    @ViewBuilder
    var playSection: some View {
        Section {
            Button {
                playSample()
            } label: {
                HStack(spacing: 8) {
                    if isSynthesizing || isPreparing {
                        ProgressView()
                    } else {
                        Image(systemName: "play.circle.fill")
                    }
                    Text(isPreparing ? "Đang nạp engine…" : (isSynthesizing ? "Đang tổng hợp…" : "Phát thử"))
                }
            }
            .disabled(!canPlay)

            Button(role: .destructive) {
                stopPlayback()
            } label: {
                Label("Dừng", systemImage: "play.slash")
            }
            .disabled(player == nil && synthesisTask == nil)
        } footer: {
            if isBlockedByPlayback {
                Text("Đang đọc truyện — hãy dừng TTS trước khi thử, vì hai bên dùng chung phiên âm thanh.")
            } else {
                Text("Engine này **không** chạy lớp tiền xử lý của NghiTTS (đọc số, phiên âm Anh/Nhật) — chỉ lớp thay thế ký tự dùng chung. Số và viết tắt do bộ G2P của model tự lo.")
            }
        }
    }
}

extension VieNeuSynthesisPolicy.Mode {
    /// Nhãn hiển thị. Ở tầng View để policy không chứa chuỗi UI.
    var displayName: String {
        switch self {
        case .high: return "Chất lượng cao · 16 bước"
        case .fast: return "Cân bằng · 8 bước"
        case .turbo: return "Nhanh nhất · 8 bước, tắt CFG"
        }
    }
}
