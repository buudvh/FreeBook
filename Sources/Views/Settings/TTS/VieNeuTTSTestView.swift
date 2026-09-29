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
/// Nút phát bị chặn khi TTS đang đọc truyện — cùng lý do đã ghi ở `NghiTTSTextToolView`: chung engine và
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
    @State var player: AVAudioPlayer?
    @State var synthesisTask: Task<Void, Never>?
    @State var didCopy = false

    var service: VieNeuTTSService? { VieNeuTTSService.shared }

    var store: VieNeuModelStore? { service?.modelStore }

    var isBlockedByPlayback: Bool {
        TTSManager.shared.isPlaying || TTSManager.shared.showFloatingWidget
    }

    var isModelReady: Bool { store?.isReady ?? false }

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
        .navigationTitle("Thử giọng VieNeu")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadVoices)
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
        if let catalog = try? service.availableVoices() {
            voices = catalog
        }
        if selectedVoice.isEmpty {
            selectedVoice = voices.first(where: { $0.name == service.defaultVoiceName })?.name
                ?? voices.first?.name
                ?? ""
        }
    }

    func download() {
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

    func deleteModel() {
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

    func playSample() {
        guard let service else { return }
        stopPlayback()
        let voice = selectedVoice
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
                // Tổng hợp **luôn ở 1.0×**: `speed` của engine đổi độ dài audio do model sinh ra, tức
                // đẩy model ra khỏi tốc độ nó được huấn luyện và bắt tổng hợp lại mỗi lần đổi tốc độ.
                // Tốc độ người dùng chọn được áp ở tầng **phát** (`AVAudioPlayer.rate`).
                let result = try await service.synthesizeWithDuration(
                    text: content,
                    voice: voice,
                    speed: 1.0,
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
