import SwiftUI
import UIKit

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
                Text("Cần tải khoảng 343 MB: 4 graph ONNX + `config.json` + `constants.npz` từ HuggingFace, `voices_v3_nano.json` và `sea_g2p.bin` từ GitHub. Cả ba nguồn đều **ghim sha** nên tác giả đổi file cũng không làm app hỏng. Gói graph **nhân bản giọng** (~91 MB) là tuỳ chọn, tải riêng ở “Giọng của tôi”.")
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
            Text("Engine local, chạy hoàn toàn trên máy. Giọng đọc không nằm trong file model mà là hai mảng số trong `voices_v3_nano.json`, nên 11 giọng dùng chung một bộ graph. Gói graph **nhân bản giọng** (~91 MB, 3 file) là **tuỳ chọn**: chỉ cần khi bạn muốn tạo giọng mới từ audio mẫu — vào “Giọng của tôi” để tải riêng.")
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
            // Lối vào giọng nhân bản. Điều kiện **không** gồm gói graph clone: màn đó tự có nút tải gói ấy.
            if isModelReady {
                NavigationLink(destination: VieNeuVoiceLibraryView()) {
                    Label("Giọng của tôi (nhân bản từ audio mẫu)", systemImage: "person.wave.2")
                }
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

                // Phát / Dừng căn **sang phải** (user 2026-09-30), tách khỏi nhóm xoá-sao chép-dán.
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
            // `.borderless` là bắt buộc: trong một hàng của `Form`, mặc định cả hàng là **một** nút nên
            // mọi cú chạm đều rơi vào nút đầu tiên.
            .buttonStyle(.borderless)
        } header: {
            Text("Chữ cần đọc")
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
            Text("Chỉ đổi tốc độ **phát**, không đổi tốc độ **tạo**: audio luôn được tổng hợp ở 1.0× rồi phát nhanh/chậm hơn. Nhờ vậy giọng luôn ở đúng tốc độ model được huấn luyện, đổi tốc độ là tức thì (không phải tổng hợp lại), và số RTF đo được luôn ứng với 1.0×.")
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
            Picker("Chế độ", selection: $selectedMode) {
                Text("Tự động (theo tốc độ máy)").tag(VieNeuSynthesisPolicy.Mode?.none)
                ForEach(VieNeuSynthesisPolicy.Mode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(VieNeuSynthesisPolicy.Mode?.some(mode))
                }
            }
            .onChange(of: selectedMode) { _, newValue in
                service?.preferredMode = newValue
            }
            // Nhãn đọc `selectedMode` (@State) trước, rồi mới tới `service.currentMode`. Đọc thẳng service
            // thì SwiftUI không biết nó đổi (class thường, không `@Observable`) và nhãn chỉ nhảy khi có
            // state khác đổi — đúng triệu chứng "chọn xong không đổi, bấm Phát mới đổi".
            LabeledContent("Đang chạy", value: activeModeName)
        } header: {
            Text("Tốc độ tạo audio")
        } footer: {
            Text("Mỗi bước là một lượt `vector_estimator`, và CFG chạy thêm **một lượt nữa cho mỗi bước** — nên mỗi đoạn tốn: “Chất lượng cao” 32 lượt (16 bước), “Cân bằng” 16 lượt (8 bước). Giảm số bước là cách duy nhất vừa nhanh hơn vừa **mát máy hơn**; đổi lại chất lượng giọng giảm. Bản tham chiếu của model khuyến nghị cặp 8 bước + sway −1. Việc giảm **độ lớn** CFG không tiết kiệm gì: engine chỉ hỏi `cfg > 0` rồi chạy đủ hai nhánh, không theo tỉ lệ.")
        }
    }

    /// Tên chế độ đang chạy. Ưu tiên lựa chọn của người dùng (state, cập nhật tức thì); khi ở "Tự động"
    /// thì hiện chế độ mà bộ thích nghi đang dùng.
    var activeModeName: String {
        selectedMode?.displayName ?? service?.currentMode.displayName ?? "—"
    }

    @ViewBuilder
    var playSection: some View {
        Section {
            // Trạng thái đang chạy vẫn cần chữ; nút Phát/Dừng đã chuyển lên hàng icon ở ô nhập chữ.
            LabeledContent(
                "Trạng thái",
                value: isPreparing ? "Đang nạp engine…" : (isSynthesizing ? "Đang tổng hợp…" : "Sẵn sàng")
            )

            // Chia sẻ file WAV vừa tạo — để gửi audio đi nghe lại ở nơi khác, không phải chụp màn hình
            // cũng không phải đoán qua mô tả.
            if let shareURL {
                ShareLink(item: shareURL) {
                    Label("Chia sẻ audio", systemImage: "square.and.arrow.up")
                }
            }
        } footer: {
            if isBlockedByPlayback {
                Text("Đang đọc truyện — hãy dừng TTS trước khi thử, vì hai bên dùng chung phiên âm thanh.")
            } else {
                Text("Màn này đi **cùng đường** với Reader: thay thế ký tự (`TTSReplacementManager`) → cắt đoạn bằng `NghiUtteranceSegmenter` theo `chunkLength` của VieNeu → tổng hợp từng đoạn với `boundaryKind` riêng rồi ghép lại. Lớp đọc số/ngày do tầng engine lo; VieNeu **không** dùng lớp phiên âm Anh/Nhật của NghiTTS — số và viết tắt do bộ G2P của model tự xử.")
            }
        }
    }
}

extension VieNeuSynthesisPolicy.Mode {
    /// Nhãn hiển thị. Ở tầng View để policy không chứa chuỗi UI.
    var displayName: String {
        switch self {
        case .high: return "Chất lượng cao"
        case .fast: return "Cân bằng"
        }
    }
}
