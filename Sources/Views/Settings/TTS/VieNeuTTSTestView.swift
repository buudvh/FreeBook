import SwiftUI
import AVFoundation
import UIKit

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
/// Nút phát bị chặn khi TTS đang đọc truyện — cùng lý do đã ghi ở `NghiTTSSettingsHubView`: chung engine và
/// chung `AVAudioSession`.
struct VieNeuTTSTestView: View {
    @State var text = "Xin chào, đây là bản thử giọng đọc VieNeu-TTS."
    @State var speed: Double = 1.0
    @State var selectedVoice = ""
    @State var voices: [Voice] = []
    @State var isPreparing = false
    @State var isSynthesizing = false
    @State var isDownloading = false
    @State var downloadProgress: Double = 0
    @State var downloadMessage = ""
    @State var statusMessage = ""
    @State var isError = false
    @State var lastReport = ""
    /// Số **đoạn** mà `NghiUtteranceSegmenter` cắt ra ở lượt gần nhất — đúng con số Reader dùng, khác
    /// `service.lastChunkCount` (số chunk *bên trong* engine cho một đoạn).
    @State var lastSegmentCount = 0
    /// Tổng `service.lastChunkCount` qua các đoạn — chỉ số bắt lỗi "một câu ngắn mà ra nhiều chunk".
    @State var lastEngineChunkCount = 0
    @State var player: AVAudioPlayer?
    @State var synthesisTask: Task<Void, Never>?
    @State var didCopy = false
    /// Lựa chọn chế độ **giữ ở tầng View**. Phải là `@State` để SwiftUI vẽ lại ngay khi đổi: `service` là
    /// class thường (không `@Observable`), nên nếu chỉ đọc `service.preferredMode` thì nhãn "Đang chạy"
    /// chỉ cập nhật khi có state KHÁC đổi — đúng triệu chứng "chọn xong không thấy đổi, bấm Phát mới đổi".
    @State var selectedMode: VieNeuSynthesisPolicy.Mode?
    /// File WAV tạm của lượt tổng hợp gần nhất, để `ShareLink` chia sẻ.
    @State var shareURL: URL?
    /// Từ điển tiếng Nhật của VieNeu: đã có dưới máy chưa, và đang tải hay không.
    @State var japaneseDictDownloaded = VieNeuJapaneseDictionary.existsOnDisk()
    @State var isDownloadingJapaneseDict = false

    var service: VieNeuTTSService? { VieNeuTTSService.shared }

    var store: VieNeuModelStore? { service?.modelStore }

    var isBlockedByPlayback: Bool {
        TTSManager.shared.isPlaying || TTSManager.shared.showFloatingWidget
    }

    var isModelReady: Bool { (store?.isReady ?? false) || (store?.coreMLReady ?? false) }

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
            japaneseDictionarySection
            textSection
            speedSection
            qualitySection
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

            // Nút này tồn tại vì một lý do cụ thể: khi engine lỗi, thứ cần thiết là **nguyên văn thông
            // báo**, mà chụp màn hình thì mất chữ và mất luôn phần số đo. Sao chép ra một khối văn bản
            // thì dán thẳng vào chat là đủ để chẩn đoán.
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
                Text("Sao chép cả thông báo lỗi, số đo RTF và trạng thái model — dán vào chat là đủ để tìm nguyên nhân, không cần chụp màn hình.")
            }
        }
        .tint(.white)
        .navigationTitle("Cài đặt VieNeu TTS")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadVoices()
            // Từ điển có thể vừa được tải ở màn khác (Cài đặt TTS) ⇒ đọc lại từ đĩa mỗi lần mở màn.
            japaneseDictDownloaded = VieNeuJapaneseDictionary.existsOnDisk()
        }
        .onDisappear(perform: stopPlayback)
    }

    // MARK: - Các khối


    // MARK: - Hành động

    /// Toàn bộ thông tin chẩn đoán gom thành **một khối văn bản** để sao chép một lần.
    ///
    /// Cố ý gồm cả những thứ trông thừa (số ký tự, trạng thái model, engine status): khi báo lỗi, thông
    /// tin thiếu thường đắt hơn thông tin thừa — và người dùng chỉ phải bấm một nút.

    private func loadVoices() {
        guard let service, isModelReady else { return }
        // Nạp lựa chọn đã lưu vào `@State` — nguồn sự thật để vẽ UI là state, không phải service.
        selectedMode = service.preferredMode
        if let catalog = try? service.availableVoices() {
            voices = catalog
        }
        if selectedVoice.isEmpty {
            selectedVoice = voices.first(where: { $0.name == service.defaultVoiceName })?.name
                ?? voices.first?.name
                ?? ""
        }
    }

    /// Tổng hợp **đúng đường Reader** (plan §2.2).
    ///
    /// Ba bước phải trùng với `TTSManager` thì số đo ở đây mới nói được điều gì về lúc đọc truyện:
    /// 1. thay thế ký tự — `TTSReplacementManager.applyReplacements`, đúng như `speakCurrent` (`:2422`);
    /// 2. cắt đoạn — `NghiUtteranceSegmenter.expand(…, maximumLength: chunkLength)`, đúng như
    ///    `playbackParagraphs` (`:798-801`);
    /// 3. tổng hợp **từng đoạn** với `boundaryKind` của chính nó, không phải `boundaryKind` mặc định.
    ///
    /// Lớp đọc số/ngày (`TextPreprocessor.normalizeVietnameseText`) **không** lặp ở đây: tầng service đã
    /// gọi (`VieNeuTTSService.executeInternalSynthesis` `:261`), gọi lại là xử lý hai lượt.
    func playSample() {
        guard let service else { return }
        stopPlayback()
        let voice = selectedVoice

        let processed = TTSReplacementManager.shared.applyReplacements(to: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !processed.isEmpty else {
            isError = true
            statusMessage = "Không còn chữ để đọc sau khi áp quy tắc thay thế ký tự."
            return
        }

        let paragraphs = NghiUtteranceSegmenter.expand(
            [TTSParagraph(
                text: processed,
                range: NSRange(location: 0, length: processed.utf16.count),
                paragraphIndex: 0
            )],
            maximumLength: TTSManager.vieNeuChunkLength
        )
        guard !paragraphs.isEmpty else { return }

        isSynthesizing = true
        isError = false
        statusMessage = ""
        lastReport = ""
        lastSegmentCount = paragraphs.count
        lastEngineChunkCount = 0

        synthesisTask = Task {
            do {
                // Nạp 4 session + `sea_g2p.bin` (62,8 MB) — chỉ xảy ra ở lượt đầu.
                if !service.isPrepared {
                    await MainActor.run { isPreparing = true }
                    try await service.prepare(voice: voice)
                    await MainActor.run { isPreparing = false }
                }

                var parts: [Data] = []
                var engineChunks = 0
                var audioSeconds = 0.0
                var speechSeconds = 0.0
                var synthesisMs = 0.0
                var queueWaitMs = 0.0
                var vectorMs = 0.0
                var otherMs = 0.0

                for paragraph in paragraphs {
                    // Tổng hợp ở **tốc độ tổng hợp** đã cài đặt (1.3.465), không còn cố định 1.0×: đây là
                    // cách màn thử nghe đúng thứ sẽ áp dụng khi đọc truyện. Mặc định 1,0× = hành vi cũ.
                    // Phần còn lại của tốc độ người dùng chọn vẫn áp ở tầng **phát** (`AVAudioPlayer.rate`).
                    let result = try await service.synthesizeWithDuration(
                        text: paragraph.text,
                        voice: voice,
                        speed: VieNeuSynthesisPolicy.synthesisSpeed(from: .standard),
                        boundaryKind: paragraph.boundaryKind,
                        priority: .demand
                    )
                    guard !Task.isCancelled else {
                        await MainActor.run { isSynthesizing = false }
                        return
                    }
                    parts.append(result.data)
                    engineChunks += service.lastChunkCount
                    audioSeconds += result.pcmDuration
                    speechSeconds += service.lastSpeechDuration
                    synthesisMs += result.synthesisMs
                    queueWaitMs += result.queueWaitMs
                    vectorMs += service.lastVectorMs
                    otherMs += service.lastOtherMs
                }

                guard let merged = WAVConcatenator.concatenate(parts) else {
                    await MainActor.run {
                        isSynthesizing = false
                        isError = true
                        statusMessage = "Ghép audio thất bại: WAV của engine không đúng khuôn 44 byte."
                    }
                    return
                }

                await MainActor.run {
                    isSynthesizing = false
                    lastEngineChunkCount = engineChunks
                    presentReport(
                        audioSeconds: audioSeconds,
                        speechSeconds: speechSeconds,
                        synthesisMs: synthesisMs,
                        queueWaitMs: queueWaitMs,
                        vectorMs: vectorMs,
                        otherMs: otherMs
                    )
                    play(merged)
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

    /// Báo cáo RTF cho **cả lượt thử**, cộng dồn qua các đoạn.
    ///
    /// Cộng dồn chứ không lấy số của đoạn cuối: số đo của một đoạn đơn lẻ không nói được gì về chi phí
    /// thật khi đọc một chương dài, mà đó chính là câu hỏi màn thử này tồn tại để trả lời.
    private func presentReport(
        audioSeconds: Double,
        speechSeconds: Double,
        synthesisMs: Double,
        queueWaitMs: Double,
        vectorMs: Double,
        otherMs: Double
    ) {
        let audio = max(audioSeconds, 0.001)
        let rtf = (synthesisMs / 1_000) / audio
        // RTF trên **audio thật** (trừ khoảng nghỉ engine tự chèn). Khoảng nghỉ không tốn thời gian suy
        // luận nên nếu tính vào tổng độ dài thì RTF bị **thấp giả** — và càng nhiều chunk càng thấp giả.
        let speech = max(speechSeconds, 0.001)
        let speechRTF = (synthesisMs / 1_000) / speech
        statusMessage = String(
            format: "Xong: %.2f giây audio, tổng hợp %.2f giây.",
            audio, synthesisMs / 1_000
        )
        lastReport = """
        đoạn         \(lastSegmentCount)   (cắt bằng `NghiUtteranceSegmenter` như Reader)
        RTF          \(String(format: "%.2f", rtf))   (nhỏ hơn 1 là đọc realtime được)
        nhanh hơn    \(String(format: "%.1f", 1 / max(rtf, 0.001)))× so với realtime
        RTF thật     \(String(format: "%.2f", speechRTF))   (trừ \(String(format: "%.2f", audio - speech)) s khoảng nghỉ)
        chậm ở đâu   vector \(String(format: "%.2f", vectorMs / 1000)) s | khác \(String(format: "%.2f", otherMs / 1000)) s
        chế độ       \(service?.currentMode.rawValue ?? "?")
        tổng hợp     \(String(format: "%.0f", synthesisMs)) ms
        chờ hàng đợi \(String(format: "%.0f", queueWaitMs)) ms
        audio        \(String(format: "%.2f", audio)) s
        """
    }

    /// Ghi WAV ra thư mục tạm để `ShareLink` có URL mà chia sẻ. Xoá file của lượt trước trước khi ghi
    /// file mới — mỗi lượt phát sinh một file và thư mục tạm không tự dọn trong một phiên dài.
    func writeTemporaryAudio(_ data: Data, replacing previous: URL?) -> URL? {
        let fileManager = FileManager.default
        if let previous { try? fileManager.removeItem(at: previous) }
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("vieneu-\(Int(Date().timeIntervalSince1970)).wav")
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
