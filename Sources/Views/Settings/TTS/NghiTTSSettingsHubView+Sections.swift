import SwiftUI
import AVFoundation

extension NghiTTSSettingsHubView {
    /// Lối vào quản lý — **gom 3 nav cũ ở tab Cài đặt** về một chỗ.
    @ViewBuilder
    var managementSection: some View {
        Section {
            NavigationLink(destination: TTSModelManagerView()) {
                Label("Quản lý Model giọng đọc", systemImage: "waveform.and.mic")
            }
            NavigationLink(destination: TTSDictionaryEditView()) {
                Label("Từ điển phiên âm cá nhân", systemImage: "character.book.closed")
            }
            NavigationLink(destination: NghiTTSSettingsView()) {
                Label("Cấu hình tiền xử lý & ngắt nghỉ", systemImage: "slider.horizontal.3")
            }
        } header: {
            Text("Quản lý")
        } footer: {
            Text("Ba mục này trước đây nằm rời ở tab Cài đặt. Riêng **thử giọng** đã chuyển hẳn vào màn này nên “Cấu hình tiền xử lý & ngắt nghỉ” **không còn** nav thử giọng.")
        }
    }

    @ViewBuilder
    var textSection: some View {
        Section {
            TextEditor(text: $text)
                .frame(minHeight: 110)
                .font(.body)
        } header: {
            Text("Chữ cần đọc")
        }
    }

    @ViewBuilder
    var voiceSection: some View {
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

    @ViewBuilder
    var playSection: some View {
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
    }

    @ViewBuilder
    var resultSection: some View {
        if !statusMessage.isEmpty {
            Section("Kết quả") {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(isError ? Color.red : Color.secondary)
            }
        }
    }

    // MARK: - Hành động (chuyển nguyên từ `NghiTTSTextToolView`)

    func loadStoredSettings() {
        if selectedVoice.isEmpty {
            selectedVoice = UserDefaults.standard.string(forKey: "nghittsVoice") ?? voices.first ?? ""
        }
        if speed == 1.0 {
            let stored = UserDefaults.standard.double(forKey: "nghittsRate")
            if stored >= 0.5 && stored <= 2.0 { speed = stored }
        }
    }

    func playSample() {
        // Chốt lại ngay lúc bấm: `canPlay` chỉ được tính khi body dựng lại, mà view này **không** observe
        // `TTSManager` (luật của repo), nên trạng thái trên nút có thể đã cũ.
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

    func stopSample() {
        synthesisTask?.cancel()
        synthesisTask = nil
        player?.stop()
        player = nil
        isSynthesizing = false
    }

    /// Bật phiên âm thanh cho clip thử. Không `setActive(false)` khi xong: `TTSManager` là chủ phiên và tự lo
    /// việc đó ở `stopPlayback`; tắt ở đây có thể cắt phiên của nó nếu người dùng phát ngay sau.
    func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
    }
}
