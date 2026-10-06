import AVFoundation
import SwiftUI
import UIKit

/// Màn thử **Kokoro-Vietnamese**: tải model, chọn giọng, nghe thử, và **đo** RTF/RAM.
///
/// Cấu trúc bám đúng thứ tự khối của `VieNeuTTSTestView.swift:68-111` — Model → Giọng đọc → Chữ cần đọc →
/// Tốc độ phát → Tốc độ tạo audio → Phát → Kết quả → Số đo hiệu năng → Sao chép kết quả. Khác hai chỗ:
/// **không** có khối "Tiếng Nhật", và khối "Tốc độ tạo audio" là `speed` **đưa thẳng vào model** (Kokoro
/// không có vòng Euler nhiều bước như VieNeu).
///
/// ## Màn này **cần model VieNeu** có trên máy
/// Kokoro dùng chung `sea_g2p.bin` với VieNeu — đã xác minh bằng mã băm git blob rằng file pip `sea-g2p`
/// v0.10.0 dùng (chính gói `vig2p` gọi) và file ở revision VieNeu ghim là **cùng một file**
/// (`411df001…`, 62 829 820 byte). Thiếu nó thì nút tải báo đúng câu cần làm thay vì để người dùng đi tìm.
///
/// ## Nút phát bị chặn khi TTS đang đọc truyện
/// Cùng lý do đã ghi ở `VieNeuTTSTestView.swift:15-16`: chung phiên âm thanh.
struct KokoroTTSTestView: View {
    @State var text = "Xin chào, đây là bản thử giọng đọc Kokoro."
    /// Tốc độ **phát** — chỉ `AVAudioPlayer.rate`, tức thời.
    @State var speed: Double = 1.0
    /// Tốc độ **tạo audio** — chính là `speed` của model Kokoro, phải tổng hợp lại.
    @State var synthesisSpeed: Double = 1.0
    @State var selectedVoiceKey = ""
    @State var voices: [KokoroVoiceCatalog.Voice] = []
    @State var isPreparing = false
    @State var isSynthesizing = false
    @State var isDownloading = false
    @State var downloadProgress: Double = 0
    @State var downloadMessage = ""
    @State var statusMessage = ""
    @State var isError = false
    @State var lastReport = ""
    @State var playbackNote = ""
    @State var player: AVAudioPlayer?
    @State var synthesisTask: Task<Void, Never>?
    @State var didCopy = false
    /// File WAV tạm của lượt gần nhất, để `ShareLink` chia sẻ.
    @State var shareURL: URL?
    /// Bump để buộc đọc lại trạng thái kho trên đĩa sau khi tải/xoá.
    @State var modelRefreshTrigger = 0

    var engine: KokoroEngine? { KokoroEngine.shared }

    var store: KokoroModelStore? { engine?.store }

    var isBlockedByPlayback: Bool {
        TTSManager.shared.isPlaying || TTSManager.shared.showFloatingWidget
    }

    var isModelReady: Bool {
        let _ = modelRefreshTrigger
        return store?.isReady ?? false
    }

    var selectedVoice: KokoroVoiceCatalog.Voice? {
        voices.first(where: { $0.key == selectedVoiceKey })
    }

    var canPlay: Bool {
        isModelReady
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedVoice != nil
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
            synthesisSpeedSection
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

            Section {
                Button {
                    UIPasteboard.general.string = diagnosticText
                    didCopy = true
                } label: {
                    Label("Sao chép kết quả", systemImage: "doc.on.doc")
                }
                if didCopy {
                    Text("Đã sao chép toàn bộ khối chẩn đoán vào bộ nhớ tạm.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Sao chép cả thông báo lỗi, số đo RTF/RAM và kết quả đối chiếu G2P — dán vào chat là đủ để tìm nguyên nhân, không cần chụp màn hình.")
            }
        }
        .tint(.white)
        .navigationTitle("Cài đặt Kokoro TTS")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            modelRefreshTrigger += 1
            loadVoices()
        }
        .onDisappear(perform: stopPlayback)
    }

    // MARK: - Hành động

    func loadVoices() {
        guard let store, isModelReady else { return }
        if let catalog = try? KokoroVoiceCatalog.load(from: store.url(for: KokoroModelStore.voicesName)) {
            voices = catalog
        }
        if selectedVoiceKey.isEmpty || !voices.contains(where: { $0.key == selectedVoiceKey }) {
            // Mặc định `ngoc_huyen` nếu có — trùng tên với giọng Piper đã sinh mẫu trên desktop, nên so được.
            selectedVoiceKey = voices.first(where: { $0.key == "ngoc_huyen" })?.key ?? voices.first?.key ?? ""
        }
    }

    func download() {
        guard let engine else { return }
        isDownloading = true
        isError = false
        statusMessage = ""
        let client = KokoroModelClient(store: engine.store)
        Task {
            do {
                try await client.prefetch { message, fraction in
                    Task { @MainActor in
                        downloadMessage = message
                        downloadProgress = fraction
                    }
                }
                await MainActor.run {
                    isDownloading = false
                    modelRefreshTrigger += 1
                    statusMessage = "Tải xong model Kokoro."
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

    func deleteModel() {
        guard let engine else { return }
        stopPlayback()
        do {
            try engine.store.deleteAll()
            voices = []
            selectedVoiceKey = ""
            lastReport = ""
            modelRefreshTrigger += 1
            statusMessage = "Đã xoá model Kokoro. (`sea_g2p.bin` của VieNeu được giữ nguyên.)"
            isError = false
        } catch {
            isError = true
            statusMessage = "Xoá thất bại: \(error.localizedDescription)"
        }
    }

    /// Tổng hợp rồi phát.
    ///
    /// Không gọi `TextPreprocessor.normalizeVietnameseText`: Kokoro có **vocab dấu câu** và bộ G2P riêng đã
    /// xử lý số/ngày — mở rộng số thành chữ trước khi vào model là lệch khỏi bản tham chiếu.
    func playSample() {
        guard let engine, let store, let voice = selectedVoice else { return }
        stopPlayback()
        let processed = TTSReplacementManager.shared.applyReplacements(to: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !processed.isEmpty else {
            isError = true
            statusMessage = "Không còn chữ để đọc sau khi áp quy tắc thay thế ký tự."
            return
        }
        let voicepackURL = store.voicepackURL(voice.fileName)
        let synthesisSpeedValue = synthesisSpeed

        isSynthesizing = true
        isError = false
        statusMessage = ""
        lastReport = ""

        synthesisTask = Task {
            do {
                if !engine.isPrepared {
                    await MainActor.run { isPreparing = true }
                    try await engine.prepareAsync()
                    await MainActor.run { isPreparing = false }
                }
                let output = try await engine.synthesizeAsync(text: processed,
                                                              voicepackURL: voicepackURL,
                                                              speed: synthesisSpeedValue)
                await MainActor.run {
                    isSynthesizing = false
                    isPreparing = false
                    presentReport(output, voiceLabel: voice.label)
                    play(output.data)
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

    /// Báo cáo số đo của lượt thử.
    ///
    /// `RAM đỉnh` là `phys_footprint` — con số iOS dùng để quyết định jetsam, và là **nửa còn lại** của tiêu
    /// chí go/no-go (so với VieNeu). `tốc độ tạo` được ghi lại vì RTF chỉ so được khi nó bằng 1,0×.
    private func presentReport(_ output: KokoroEngine.Output, voiceLabel: String) {
        let audio = max(output.pcmDuration, 0.001)
        let rtf = (output.synthesisMs / 1_000) / audio
        statusMessage = String(format: "Xong: %.2f giây audio, tổng hợp %.2f giây.",
                               audio, output.synthesisMs / 1_000)
        lastReport = """
        âm vị         \(output.phonemeCount)   (một lượt cho cả câu)
        RTF          \(String(format: "%.2f", rtf))   (nhỏ hơn 1 là đọc realtime được)
        nhanh hơn    \(String(format: "%.1f", 1 / max(rtf, 0.001)))× so với realtime
        — chia thời gian —
        G2P          \(String(format: "%.0f", output.g2pMs)) ms
        graph ONNX   \(String(format: "%.0f", output.sessionMs)) ms
        — tài nguyên —
        nạp model    \(String(format: "%.1f", output.loadMs / 1_000)) s   (một lần cho cả phiên)
        RAM đỉnh     \(ProcessMemory.formatted())
        lấy mẫu      \(output.sampleRate) Hz
        tốc độ tạo   \(String(format: "%.2f", synthesisSpeed))×   (RTF chỉ so được khi = 1,00×)
        nhiệt · pin  \(ProcessMemory.thermalStateName())\(ProcessMemory.isLowPowerModeEnabled ? " · TIẾT KIỆM PIN BẬT" : "")
        đỉnh biên độ \(String(format: "%.3f", output.peakAmplitude))
        chữ → âm vị  \(output.characterCount) → \(output.phonemeCount)
        giọng        \(voiceLabel)
        — đối chiếu —
        \(output.g2pReport)
        """
    }

    /// Ghi WAV ra thư mục tạm để `ShareLink` có URL. Xoá file lượt trước trước khi ghi file mới.
    func writeTemporaryAudio(_ data: Data, replacing previous: URL?) -> URL? {
        let fileManager = FileManager.default
        if let previous { try? fileManager.removeItem(at: previous) }
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("kokoro-\(Int(Date().timeIntervalSince1970)).wav")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func play(_ data: Data) {
        shareURL = writeTemporaryAudio(data, replacing: shareURL)
        playbackNote = ""

        // Kích hoạt phiên âm thanh **tường minh** trước khi phát — bài học từ màn thử ZeroTTS: `AVAudioPlayer`
        // chỉ kích hoạt **ngầm**, và khi phiên đã bị `setActive(false)` ở nơi khác thì việc kích hoạt ngầm có
        // thể không thành công — im lặng, không lỗi.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
            playbackNote = "phiên \(session.category.rawValue) đã kích hoạt"
        } catch {
            playbackNote = "phiên: LỖI \(error.localizedDescription)"
        }

        do {
            let newPlayer = try AVAudioPlayer(data: data)
            player = newPlayer
            // `enableRate` phải bật **trước** khi đặt `rate`, nếu không iOS bỏ qua giá trị.
            newPlayer.enableRate = true
            newPlayer.rate = Float(speed)
            newPlayer.prepareToPlay()
            let started = newPlayer.play()
            playbackNote += started
                ? String(format: " · play() = true · %.2f s", newPlayer.duration)
                : " · play() = FALSE"
        } catch {
            isError = true
            playbackNote += " · AVAudioPlayer lỗi: \(error.localizedDescription)"
            statusMessage = "Phát thất bại: \(error.localizedDescription)"
        }
    }

    func stopPlayback() {
        synthesisTask?.cancel()
        synthesisTask = nil
        player?.stop()
        player = nil
        isSynthesizing = false
        isPreparing = false
    }
}
