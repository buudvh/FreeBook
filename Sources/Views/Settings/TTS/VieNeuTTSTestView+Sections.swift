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

    /// Lối vào **từ điển tiếng Nhật** của VieNeu: đã tải ⇒ `NavigationLink`; chưa tải ⇒ cảnh báo + nút tải.
    ///
    /// Hai **công tắc** áp dụng (`Áp dụng từ điển phiên âm VieNeu`, `Tự động phiên âm tiếng Nhật`) **không**
    /// ở đây — chúng chỉ có ở *Cài đặt TTS → Quản lý riêng của trình đọc* (người dùng chốt 2026-10-01), nên
    /// màn này chỉ mở lối vào và nói rõ điều đó ở footer.
    @ViewBuilder
    var japaneseDictionarySection: some View {
        Section {
            if japaneseDictDownloaded {
                NavigationLink(destination: VieNeuJapaneseDictionaryView()) {
                    Label("Từ điển phiên âm tiếng Nhật", systemImage: "character.book.closed")
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text("Chưa tải từ điển tiếng Nhật").font(.subheadline).foregroundColor(.secondary)
                }
                Button {
                    downloadJapaneseDictionary()
                } label: {
                    Label("Tải từ điển tiếng Nhật", systemImage: "arrow.down.circle")
                }
                .disabled(isDownloadingJapaneseDict)
            }
        } header: {
            Text("Tiếng Nhật")
        } footer: {
            Text("Từ điển **riêng của VieNeu**, độc lập với từ điển của NghiTTS. Bật/tắt áp dụng ở **Cài đặt TTS → Quản lý riêng của trình đọc**; cả hai công tắc ở đó mặc định **tắt**.")
        }
    }

    /// Tải từ điển tiếng Nhật rồi cập nhật cờ "đã tải" ⇒ hàng cảnh báo đổi thành lối vào ngay.
    func downloadJapaneseDictionary() {
        isDownloadingJapaneseDict = true
        Task {
            do {
                try await VieNeuJapaneseDictionary.shared.downloadInitialDictionary()
                japaneseDictDownloaded = VieNeuJapaneseDictionary.existsOnDisk()
                ToastManager.shared.show(message: "Tải từ điển tiếng Nhật thành công!", type: .success)
            } catch {
                ToastManager.shared.show(message: "Không thể tải từ điển: \(error.localizedDescription)", type: .error)
            }
            isDownloadingJapaneseDict = false
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

    // MARK: - Model VieNeu (ONNX) — lối tải lần đầu (plan 1.3.494, B4)

    /// Đường tải model VieNeu khi chưa có gì — bù đắp cho việc `vieNeuDownloadRow` đã chuyển từ
    /// Section 1 lên Section 3 (chỉ hiện khi chọn engine `vieneu`). Màn này luôn với tới được từ
    /// `TTSSettingsSection`, nên là lối vào tải model an toàn ngay cả trước lần chọn engine đầu tiên.
    @ViewBuilder
    var modelSection: some View {
        Section {
            if let store, store.isReady {
                LabeledContent("Trạng thái", value: "Đã tải đủ 8 file")
                LabeledContent("Dung lượng", value: formattedBytes(store.totalBytes))
                NavigationLink(destination: VieNeuModelManagerView()) {
                    Label("Quản lý model VieNeu", systemImage: "cpu")
                }
                Button(role: .destructive) {
                    deleteVieNeuModel()
                } label: {
                    Label("Xoá model ONNX", systemImage: "trash")
                }
            } else {
                LabeledContent("Còn thiếu", value: "\(store?.missingNames.count ?? 0) file")
                Text("Cần tải khoảng 343 MB: 4 graph ONNX + config.json + constants.npz từ HuggingFace, voices_v3_nano.json và sea_g2p.bin từ GitHub. Cả ba nguồn đều ghim sha nên tác giả đổi file cũng không làm app hỏng.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isDownloading {
                    ProgressView(value: downloadProgress) {
                        Text(downloadMessage)
                            .font(.caption)
                    }
                } else {
                    Button {
                        downloadVieNeuModel()
                    } label: {
                        Label("Tải model VieNeu (ONNX)", systemImage: "arrow.down.circle")
                    }
                    .disabled(service == nil)
                }
            }
        } header: {
            Text("Model VieNeu (ONNX)")
        } footer: {
            Text("Bắt buộc để dùng VieNeu-TTS. Sau khi tải xong có thể bật Core ML (thử nghiệm) ở Cài đặt TTS để tăng tốc.")
        }
    }

    /// Tải model ONNX (4 graph + config + 2 asset, ~343 MB) — nền luôn trú và là fallback của Core ML.
    /// Tái dùng `VieNeuModelClient.prefetch` giống `VieNeuModelManagerView.downloadModel`.
    func downloadVieNeuModel() {
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

    /// Xoá model ONNX (không đụng Core ML, không đụng giọng user).
    func deleteVieNeuModel() {
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

    func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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
