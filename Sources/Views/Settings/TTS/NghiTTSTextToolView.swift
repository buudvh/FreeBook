import SwiftUI
import AVFoundation

/// Công cụ thử giọng NghiTTS: nhập chữ, chọn giọng, chỉnh tốc độ, bấm phát.
///
/// Dùng lại **đúng** `PiperTTSService` của `TTSManager` chứ không tạo service riêng: một service mới
/// nghĩa là một `ORTSession` thứ hai nằm trong RAM và một đường tổng hợp không đi qua
/// `PiperSynthesisCoordinator` — trái với bất biến "chỉ một operation tổng hợp tại một thời điểm".
///
/// Nút phát bị chặn khi TTS đang đọc truyện: hai bên dùng chung engine và chung `AVAudioSession`, chạy
/// song song chỉ tạo ra tranh chấp và một lượt suy luận ONNX vô ích.
struct NghiTTSTextToolView: View {
    @State private var text = "Xin chào, đây là bản thử giọng đọc."
    @State private var speed: Double = 1.0
    @State private var selectedVoice = ""
    @State private var isSynthesizing = false
    @State private var statusMessage = ""
    @State private var isError = false
    @State private var player: AVAudioPlayer?
    @State private var synthesisTask: Task<Void, Never>?

    /// `ModelStore.init` co the throw (khong dung duoc thu muc model); khi do coi nhu chua co giong.
    private let voices: [String] = (try? ModelStore())?.getLocalVoiceIDs() ?? []

    private var isBlockedByPlayback: Bool {
        TTSManager.shared.isPlaying || TTSManager.shared.showFloatingWidget
    }

    private var canPlay: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedVoice.isEmpty
            && !isSynthesizing
            && !isBlockedByPlayback
    }

    var body: some View {
        Form {
            Section("Chữ cần đọc") {
                TextEditor(text: $text)
                    .frame(minHeight: 110)
                    .font(.body)
            }

            Section("Giọng đọc") {
                if voices.isEmpty {
                    Text("Chưa có giọng NghiTTS nào được tải về.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Giọng", selection: $selectedVoice) {
                        ForEach(voices, id: \.self) { voice in
                            Text(voice).tag(voice)
                        }
                    }
                }
            }

            Section("Tốc độ") {
                HStack {
                    Text("0.5×").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $speed, in: 0.5...2.0, step: 0.05)
                    Text("2.0×").font(.caption2).foregroundStyle(.secondary)
                }
                LabeledContent("Đang chọn", value: String(format: "%.2f×", speed))
            }

            Section {
                Button {
                    playSample()
                } label: {
                    HStack(spacing: 8) {
                        if isSynthesizing {
                            ProgressView()
                        } else {
                            Image(systemName: "play.circle.fill")
                        }
                        Text(isSynthesizing ? "Đang tổng hợp…" : "Phát thử")
                    }
                }
                .disabled(!canPlay)

                Button(role: .destructive) {
                    stopSample()
                } label: {
                    Label("Dừng", systemImage: "stop.circle")
                }
                .disabled(player == nil && !isSynthesizing)
            } footer: {
                if isBlockedByPlayback {
                    Text("Đang đọc truyện — hãy dừng TTS trước khi thử, vì hai bên dùng chung engine và chung phiên âm thanh.")
                } else {
                    Text("Chuỗi được đưa qua **đúng** đường tiền xử lý của NghiTTS (đọc số, phiên âm, từ điển thay thế) trước khi tổng hợp, nên nghe được y như lúc đọc truyện.")
                }
            }

            if !statusMessage.isEmpty {
                Section("Kết quả") {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(isError ? Color.red : Color.secondary)
                }
            }
        }
        .navigationTitle("Thử giọng đọc")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedVoice.isEmpty {
                selectedVoice = UserDefaults.standard.string(forKey: "nghittsVoice") ?? voices.first ?? ""
            }
            if speed == 1.0 {
                let stored = UserDefaults.standard.double(forKey: "nghittsRate")
                if stored >= 0.5 && stored <= 2.0 { speed = stored }
            }
        }
        .onDisappear {
            stopSample()
        }
    }

    // MARK: - Hành động

    private func playSample() {
        // Chốt lại ngay lúc bấm: `canPlay` chỉ được tính khi body dựng lại, mà view này **không**
        // observe `TTSManager` (luật của repo), nên trạng thái trên nút có thể đã cũ.
        guard !isBlockedByPlayback else {
            isError = true
            statusMessage = "Đang đọc truyện — hãy dừng TTS trước khi thử."
            return
        }
        guard let service = TTSManager.shared.nghiTTSService else {
            isError = true
            statusMessage = "Chưa khởi tạo được engine NghiTTS."
            return
        }
        let payloadText = text
        let voice = selectedVoice
        let rate = speed

        stopSample()
        isSynthesizing = true
        isError = false
        statusMessage = ""

        synthesisTask = Task { @MainActor in
            do {
                let started = Date()
                let data = try await service.synthesize(text: payloadText, voice: voice, speed: rate)
                guard !Task.isCancelled else { return }
                try activateSession()
                let newPlayer = try AVAudioPlayer(data: data)
                newPlayer.enableRate = true
                newPlayer.prepareToPlay()
                player = newPlayer
                newPlayer.play()
                isSynthesizing = false
                statusMessage = String(
                    format: "Đã tổng hợp %.0f KB trong %.2f giây, dài %.2f giây.",
                    Double(data.count) / 1024,
                    Date().timeIntervalSince(started),
                    newPlayer.duration
                )
            } catch is CancellationError {
                isSynthesizing = false
            } catch {
                isSynthesizing = false
                isError = true
                statusMessage = "Lỗi: \(error.localizedDescription)"
            }
        }
    }

    private func stopSample() {
        synthesisTask?.cancel()
        synthesisTask = nil
        player?.stop()
        player = nil
        isSynthesizing = false
    }

    /// Bật phiên âm thanh cho clip thử. Không `setActive(false)` khi xong: `TTSManager` là chủ phiên và
    /// tự lo việc đó ở `stopPlayback`; tắt ở đây có thể cắt phiên của nó nếu người dùng phát ngay sau.
    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
    }
}
