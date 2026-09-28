import SwiftUI
import AVFoundation

/// Màn thử giọng **VieNeu-TTS v3 Nano**: tải model, chọn giọng, nghe thử, và **đo RTF thật**.
///
/// Vì sao cần màn riêng thay vì thêm thẳng vào Picker "Trình đọc": engine chỉ dùng được nếu RTF < 1 trên
/// máy thật, mà con số 0,11–0,22 của tác giả model là **CPU desktop 6 luồng**, không phải iPhone. Nối
/// vào Reader trước khi đo là làm một việc lớn (hơn 40 điểm chạm `"nghitts"` trong `TTSManager` và
/// `TTSSettingsView`) mà chưa biết có dùng được hay không. Màn này trả lời câu hỏi đó trước.
///
/// Dùng **đúng** `VieNeuTTSService.shared` mà tầng Reader sẽ dùng, không tạo thực thể thứ hai: mỗi
/// `VieNeuTTSEngine` giữ bốn `ORT` session riêng nên hai service là hai bộ session trong RAM.
///
/// Nút phát bị chặn khi TTS đang đọc truyện — cùng lý do đã ghi ở `NghiTTSTextToolView`: chung engine và
/// chung `AVAudioSession`.
struct VieNeuTTSTestView: View {
    @State private var text = "Xin chào, đây là bản thử giọng đọc VieNeu-TTS."
    @State private var speed: Double = 1.0
    @State private var selectedVoice = ""
    @State private var voices: [Voice] = []
    @State private var isPreparing = false
    @State private var isSynthesizing = false
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadMessage = ""
    @State private var statusMessage = ""
    @State private var isError = false
    @State private var lastReport = ""
    @State private var player: AVAudioPlayer?
    @State private var synthesisTask: Task<Void, Never>?

    private var service: VieNeuTTSService? { VieNeuTTSService.shared }

    private var store: VieNeuModelStore? { service?.modelStore }

    private var isBlockedByPlayback: Bool {
        TTSManager.shared.isPlaying || TTSManager.shared.showFloatingWidget
    }

    private var isModelReady: Bool { store?.isReady ?? false }

    private var canPlay: Bool {
        isModelReady
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedVoice.isEmpty
            && !isSynthesizing
            && !isPreparing
            && !isBlockedByPlayback
    }

    var body: some View {
        Form {
            modelSection
            voiceSection
            textSection
            speedSection
            playSection

            if !statusMessage.isEmpty {
                Section("Kết quả") {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(isError ? Color.red : Color.secondary)
                }
            }

            if !lastReport.isEmpty {
                Section("Số đo hiệu năng") {
                    Text(lastReport)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(.white)
        .navigationTitle("Thử giọng VieNeu")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadVoices)
        .onDisappear(perform: stopPlayback)
    }

    // MARK: - Các khối

    @ViewBuilder
    private var modelSection: some View {
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
    private var voiceSection: some View {
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
    private var textSection: some View {
        Section("Chữ cần đọc") {
            TextEditor(text: $text)
                .frame(minHeight: 110)
                .font(.body)
        }
    }

    @ViewBuilder
    private var speedSection: some View {
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

    @ViewBuilder
    private var playSection: some View {
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

    // MARK: - Hành động

    private func loadVoices() {
        guard let service, isModelReady else { return }
        if let catalog = try? service.availableVoices() {
            voices = catalog
        }
        if selectedVoice.isEmpty {
            selectedVoice = voices.first(where: { $0.name == service.defaultVoiceName })?.name
                ?? voices.first?.name
                ?? ""
        }
    }

    private func download() {
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
                    statusMessage = "Tải xong model VieNeu."
                    loadVoices()
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    isError = true
                    statusMessage = "Tải thất bại: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteModel() {
        guard let service else { return }
        stopPlayback()
        do {
            try service.modelStore.deleteAll()
            voices = []
            selectedVoice = ""
            lastReport = ""
            statusMessage = "Đã xoá model VieNeu."
            isError = false
        } catch {
            isError = true
            statusMessage = "Xoá thất bại: \(error.localizedDescription)"
        }
    }

    private func playSample() {
        guard let service else { return }
        stopPlayback()
        let voice = selectedVoice
        let rate = speed
        let content = text
        isSynthesizing = true
        isError = false
        statusMessage = ""
        lastReport = ""

        synthesisTask = Task {
            do {
                // Nạp 4 session + `sea_g2p.bin` (62,8 MB) — chỉ xảy ra ở lượt đầu.
                if !service.isPrepared {
                    await MainActor.run { isPreparing = true }
                    try await service.prepare(voice: voice)
                    await MainActor.run { isPreparing = false }
                }
                let result = try await service.synthesizeWithDuration(
                    text: content,
                    voice: voice,
                    speed: rate,
                    priority: .demand
                )
                guard !Task.isCancelled else {
                    await MainActor.run { isSynthesizing = false }
                    return
                }
                await MainActor.run {
                    isSynthesizing = false
                    presentReport(result: result)
                    play(result.data)
                }
            } catch is CancellationError {
                await MainActor.run { isSynthesizing = false; isPreparing = false }
            } catch {
                await MainActor.run {
                    isSynthesizing = false
                    isPreparing = false
                    isError = true
                    statusMessage = "Tổng hợp thất bại: \(error.localizedDescription)"
                }
            }
        }
    }

    private func presentReport(result: (data: Data, pcmDuration: Double, queueWaitMs: Double, synthesisMs: Double)) {
        let audioSeconds = max(result.pcmDuration, 0.001)
        let rtf = (result.synthesisMs / 1_000) / audioSeconds
        statusMessage = String(
            format: "Xong: %.2f giây audio, tổng hợp %.2f giây.",
            audioSeconds, result.synthesisMs / 1_000
        )
        lastReport = """
        RTF          \(String(format: "%.2f", rtf))   (nhỏ hơn 1 là đọc realtime được)
        chế độ       \(service?.currentMode.rawValue ?? "?")
        tổng hợp     \(String(format: "%.0f", result.synthesisMs)) ms
        chờ hàng đợi \(String(format: "%.0f", result.queueWaitMs)) ms
        audio        \(String(format: "%.2f", audioSeconds)) s
        """
    }

    private func play(_ data: Data) {
        do {
            let newPlayer = try AVAudioPlayer(data: data)
            player = newPlayer
            newPlayer.prepareToPlay()
            newPlayer.play()
        } catch {
            isError = true
            statusMessage = "Phát thất bại: \(error.localizedDescription)"
        }
    }

    private func stopPlayback() {
        synthesisTask?.cancel()
        synthesisTask = nil
        player?.stop()
        player = nil
        isSynthesizing = false
        isPreparing = false
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
