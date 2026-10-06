import AVFoundation
import SwiftUI
import UIKit

/// Màn thử **ZeroTTS**: tải model, chọn giọng preset, nghe thử, và **đo số hiệu năng thật**.
///
/// ## Vì sao có màn riêng thay vì thêm vào Picker "Trình đọc"
/// ZeroTTS chỉ dùng được nếu nó chạy nổi trên máy thật (RTF < 1 và không bị jetsam), mà cả hai điều đó
/// chưa ai đo. Nối vào Reader trước khi đo là sửa hàng chục điểm rẽ nhánh theo tên engine trong
/// `TTSManager`/`TTSSettingsView` để đổi lấy một thứ có thể không dùng được. Màn này trả lời câu hỏi đó
/// trước — cùng lý do đã ghi ở `VieNeuTTSTestView.swift:7-10`.
///
/// Cấu trúc các khối bám **đúng** thứ tự của `VieNeuTTSTestView` (Model → Giọng đọc → Chữ cần đọc → Tốc
/// độ phát → Lấy mẫu → Phát → Kết quả → Số đo → Sao chép). Khác duy nhất: không có khối "Tiếng Nhật"
/// (ZeroTTS không có từ điển riêng) và khối chất lượng đổi tên thành "Lấy mẫu" — kiến trúc này **không**
/// có vòng Euler nhiều bước như VieNeu, thứ vặn được chỉ là tham số lấy mẫu.
///
/// Dùng **đúng** `ZeroTTSEngine.shared` mà tầng Reader sẽ dùng, không tạo thực thể thứ hai: mỗi ngữ cảnh
/// ORT giữ bốn session riêng nên hai engine là hai bộ graph trong RAM.
struct ZeroTTSTestView: View {
    /// Hai mức lấy mẫu cho spike.
    ///
    /// Cố ý **không** có mức dùng `cfg_scale > 1`: nhánh classifier-free guidance cần batch 2
    /// (`[voice ‖ null_voice]`), mà bản port này mới chạy batch 1 — đẩy `cfg_scale` lên là đưa model vào
    /// một chế độ nó không được dựng cho.
    enum SamplingMode: String, CaseIterable, Identifiable {
        case reference = "Như bản tham chiếu"
        case calmer = "Ổn định hơn"

        var id: String { rawValue }

        var sampling: ZeroTTSConfig.Sampling {
            var sampling = ZeroTTSConfig.Sampling()
            if self == .calmer {
                sampling.audioTemperature = 0.6
                sampling.audioTopP = 0.9
            }
            return sampling
        }
    }

    @State var text = "Xin chào, đây là bản thử giọng đọc ZeroTTS."
    @State var speed: Double = 1.0
    @State var selectedVoice = ""
    @State var voices: [ZeroTTSVoiceCatalog.Voice] = []
    @State var samplingMode: SamplingMode = .reference
    @State var isPreparing = false
    @State var isSynthesizing = false
    @State var isDownloading = false
    @State var downloadProgress: Double = 0
    @State var downloadMessage = ""
    @State var statusMessage = ""
    @State var isError = false
    @State var lastReport = ""
    /// Kết quả đối chiếu tokenizer của lượt gần nhất. Giữ ở đây thay vì parse lại `tokenizer.json` (192 KB)
    /// mỗi lần bấm "Sao chép kết quả".
    @State var tokenizerReport = ""
    @State var player: AVAudioPlayer?
    @State var synthesisTask: Task<Void, Never>?
    @State var didCopy = false
    /// File WAV tạm của lượt gần nhất, để `ShareLink` chia sẻ.
    @State var shareURL: URL?
    /// Bump để buộc đọc lại trạng thái kho trên đĩa (`isReady`, dung lượng) sau khi tải/xoá.
    @State var modelRefreshTrigger = 0

    var engine: ZeroTTSEngine? { ZeroTTSEngine.shared }

    var store: ZeroTTSModelStore? { engine?.store }

    var isBlockedByPlayback: Bool {
        TTSManager.shared.isPlaying || TTSManager.shared.showFloatingWidget
    }

    var isModelReady: Bool {
        let _ = modelRefreshTrigger
        return store?.isReady ?? false
    }

    var canPlay: Bool {
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
            samplingSection
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

            // Nút này tồn tại vì một lý do cụ thể: khi engine lỗi, thứ cần là **nguyên văn thông báo** —
            // chụp màn hình thì mất chữ và mất luôn phần số đo. Sao chép ra một khối văn bản thì dán thẳng
            // vào chat là đủ để chẩn đoán.
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
                Text("Sao chép cả thông báo lỗi, số đo RTF, RAM đỉnh và kết quả đối chiếu tokenizer — dán vào chat là đủ để tìm nguyên nhân, không cần chụp màn hình.")
            }
        }
        .tint(.white)
        .navigationTitle("Cài đặt ZeroTTS TTS")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            modelRefreshTrigger += 1
            loadVoices()
        }
        .onDisappear(perform: stopPlayback)
    }

    // MARK: - Hành động

    func loadVoices() {
        guard let engine, isModelReady else { return }
        if let catalog = try? engine.availableVoices() { voices = catalog }
        if selectedVoice.isEmpty || !voices.contains(where: { $0.name == selectedVoice }) {
            selectedVoice = voices.first?.name ?? ""
        }
    }

    func download() {
        guard let engine else { return }
        isDownloading = true
        isError = false
        statusMessage = ""
        let client = ZeroTTSModelClient(store: engine.store)
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
                    statusMessage = "Tải xong model ZeroTTS."
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
            selectedVoice = ""
            lastReport = ""
            modelRefreshTrigger += 1
            statusMessage = "Đã xoá model ZeroTTS."
            isError = false
        } catch {
            isError = true
            statusMessage = "Xoá thất bại: \(error.localizedDescription)"
        }
    }

    /// Tổng hợp **một đoạn** rồi phát.
    ///
    /// Khác `VieNeuTTSTestView.playSample` ở hai điểm, cả hai đều có lý do:
    /// - **Không** cắt đoạn bằng `NghiUtteranceSegmenter`: hàm đó cắt theo `chunkLength` của engine local
    ///   khác, còn ZeroTTS tự tách chunk theo `max_chunk_sec` của chính nó. Spike chỉ đọc một câu nên
    ///   không cần tầng cắt nào.
    /// - **Không** gọi `TextPreprocessor.normalizeVietnameseText`: model tự đọc số/ngày/viết tắt, và mở
    ///   rộng số thành chữ trước khi vào model là lệch khỏi bản tham chiếu.
    func playSample() {
        guard let engine else { return }
        stopPlayback()
        let voice = selectedVoice
        let sampling = samplingMode.sampling
        let processed = TTSReplacementManager.shared.applyReplacements(to: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !processed.isEmpty else {
            isError = true
            statusMessage = "Không còn chữ để đọc sau khi áp quy tắc thay thế ký tự."
            return
        }

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
                let report = try await engine.synthesizeAsync(text: processed, voice: voice, sampling: sampling)
                await MainActor.run {
                    isSynthesizing = false
                    isPreparing = false
                    presentReport(report)
                    play(report.data)
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

    /// Báo cáo số đo của **cả lượt thử**.
    ///
    /// `RTF` tính trên audio thật; `RAM đỉnh` là `phys_footprint` sau khi tổng hợp — con số mà iOS dùng để
    /// quyết định jetsam, nên nó là nửa còn lại của câu hỏi go/no-go.
    private func presentReport(_ report: ZeroTTSEngine.Report) {
        let audio = max(report.pcmDuration, 0.001)
        let rtf = (report.synthesisMs / 1_000) / audio
        let resident = report.residentBytes > 0
            ? String(format: "%.2f GB", Double(report.residentBytes) / 1_073_741_824)
            : "—"
        statusMessage = String(format: "Xong: %.2f giây audio, tổng hợp %.2f giây.",
                               audio, report.synthesisMs / 1_000)
        tokenizerReport = report.tokenizerReport
        lastReport = """
        frame        \(report.frameCount)   (mỗi frame 80 ms ở 12,5 Hz)
        RTF          \(String(format: "%.2f", rtf))   (nhỏ hơn 1 là đọc realtime được)
        nhanh hơn    \(String(format: "%.1f", 1 / max(rtf, 0.001)))× so với realtime
        nạp model    \(String(format: "%.1f", report.loadMs / 1_000)) s   (chỉ tính lượt đầu)
        RAM đỉnh     \(resident)
        lấy mẫu      \(report.sampleRate) Hz
        chữ → token  \(report.characterCount) → \(report.textTokenCount)
        """
    }

    /// Ghi WAV ra thư mục tạm để `ShareLink` có URL. Xoá file lượt trước trước khi ghi file mới.
    func writeTemporaryAudio(_ data: Data, replacing previous: URL?) -> URL? {
        let fileManager = FileManager.default
        if let previous { try? fileManager.removeItem(at: previous) }
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("zerotts-\(Int(Date().timeIntervalSince1970)).wav")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func play(_ data: Data) {
        shareURL = writeTemporaryAudio(data, replacing: shareURL)
        do {
            let newPlayer = try AVAudioPlayer(data: data)
            player = newPlayer
            // `enableRate` phải bật **trước** khi đặt `rate`, nếu không iOS bỏ qua giá trị.
            newPlayer.enableRate = true
            newPlayer.rate = Float(speed)
            newPlayer.prepareToPlay()
            newPlayer.play()
        } catch {
            isError = true
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
