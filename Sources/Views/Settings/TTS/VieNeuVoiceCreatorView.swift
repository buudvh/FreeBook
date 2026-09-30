import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Sheet **"Tạo giọng mới"**: thu âm 3–8 giây **hoặc** chọn một file audio, nghe lại, đặt tên, lưu.
///
/// Hai đường vào nhưng **một** đầu ra: một URL audio mẫu. Việc nhân bản (nặng, mở ORT) do màn gọi
/// (`VieNeuVoiceLibraryView.enroll`) làm sau khi sheet đóng — nhờ vậy sheet không giữ ngữ cảnh ONNX
/// trong lúc người dùng còn đang cân nhắc, và có thể đóng ngay khi bấm Lưu.
///
/// **Không** xoá file audio mẫu tạm ở đường Lưu: `VieNeuCustomVoiceStore.add` **copy** nó vào
/// `CustomVoices/samples/`, nên file tạm chỉ được dọn sau khi copy xong (màn gọi làm). Đường **Huỷ** thì
/// dọn ngay, vì không ai dùng nữa.
struct VieNeuVoiceCreatorView: View {
    enum Source: String, CaseIterable, Identifiable {
        case record = "Thu âm"
        case file = "Chọn file"

        var id: String { rawValue }
    }

    let onSave: (String, URL) -> Void
    let onCancel: () -> Void

    @State private var source: Source = .record
    @State private var recorder = VieNeuVoiceRecorder()
    @State private var name = ""
    @State private var sampleURL: URL?
    @State private var isRecording = false
    @State private var elapsed: TimeInterval = 0
    @State private var level: Float = -160
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var message = ""
    @State private var isError = false
    @State private var showingFileImporter = false
    @State private var permissionDenied = false
    @State private var isProbing = false

    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var canSave: Bool {
        sampleURL != nil && !name.trimmed.isEmpty && !isRecording && !isProbing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Nguồn audio", selection: $source) {
                        ForEach(Source.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isRecording)
                }

                if source == .record {
                    recordSection
                } else {
                    fileSection
                }

                if sampleURL != nil {
                    previewSection
                }

                Section {
                    TextField("Tên giọng", text: $name)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("Tên này hiện trong danh sách chọn giọng đọc, và phải khác các giọng đang có.")
                }

                if !message.isEmpty {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(isError ? Color.red : Color.secondary)
                    }
                }
            }
            .tint(.white)
            .navigationTitle("Tạo giọng mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }
                        .disabled(!canSave)
                }
            }
            .onReceive(ticker) { _ in tick() }
            .onDisappear(perform: stopPlayer)
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { acceptFile(url) }
                case .failure(let error):
                    isError = true
                    message = "Không mở được file: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Khối

    @ViewBuilder
    private var recordSection: some View {
        Section {
            HStack {
                Button {
                    if isRecording { stopRecording() } else { startRecording() }
                } label: {
                    Label(
                        isRecording ? "Dừng thu" : "Bắt đầu thu",
                        systemImage: isRecording ? "stop.circle" : "mic.circle"
                    )
                }
                Spacer()
                Text(String(format: "%.1f s", elapsed))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(elapsed >= VieNeuVoiceCloner.recommendedSampleSeconds ? Color.orange : Color.secondary)
            }
            if isRecording {
                // Thanh nhịp: thu **im lặng** là kiểu hỏng hay gặp nhất, mà nếu không có chỉ báo thì người
                // dùng chỉ biết sau khi đã lưu và nghe thử.
                ProgressView(value: levelFraction)
            }
        } header: {
            Text("Thu âm")
        } footer: {
            Text("Nói một câu liền mạch 3–8 giây ở nơi yên tĩnh, cách micro ~20 cm. Tự dừng khi đủ \(Int(VieNeuVoiceCloner.recommendedSampleSeconds)) giây.")
        }
    }

    @ViewBuilder
    private var fileSection: some View {
        Section {
            Button {
                showingFileImporter = true
            } label: {
                Label(sampleURL == nil ? "Chọn file audio" : "Chọn file khác", systemImage: "folder")
            }
            if isProbing {
                ProgressView { Text("Đang đọc file…").font(.caption) }
            }
        } footer: {
            Text("Nhận mọi định dạng iOS đọc được (m4a, mp3, wav, caf, aiff…). Nên chọn đoạn 3–8 giây, một người nói, ít tạp âm.")
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        Section {
            Button {
                if isPlaying { stopPlayer() } else { playSample() }
            } label: {
                Label(
                    isPlaying ? "Dừng nghe" : "Nghe lại audio mẫu",
                    systemImage: isPlaying ? "stop.circle" : "play.circle"
                )
            }
        } footer: {
            Text("Nghe lại trước khi lưu. Có tạp âm hoặc lẫn tiếng người khác thì thu lại — audio mẫu quyết định gần như toàn bộ chất lượng giọng nhân bản.")
        }
    }

    // MARK: - Thu âm

    private func tick() {
        guard isRecording else { return }
        elapsed = recorder.elapsed
        level = recorder.refreshLevel()
        if elapsed >= VieNeuVoiceCloner.recommendedSampleSeconds {
            stopRecording()
        }
    }

    private var levelFraction: Double {
        // `averagePower` trả dB trong khoảng −160…0; ánh xạ −60…0 thành 0…1 để thanh nhịp còn thấy được.
        let clamped = max(-60, min(0, Double(level)))
        return (clamped + 60) / 60
    }

    private func startRecording() {
        message = ""
        Task {
            guard await VieNeuVoiceRecorder.requestPermission() else {
                permissionDenied = true
                isError = true
                message = VieNeuVoiceRecorder.RecorderError.permissionDenied.errorDescription
                    ?? "Chưa được cấp quyền micro."
                return
            }
            permissionDenied = false
            // Dừng TTS **trước** khi thu: loa đang phát sẽ lọt thẳng vào bản thu.
            TTSManager.shared.stop()
            stopPlayer()
            discardSample()
            do {
                try recorder.start()
                isRecording = true
                elapsed = 0
                isError = false
            } catch {
                isError = true
                message = error.localizedDescription
            }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let url = recorder.stop() {
            sampleURL = url
            isError = false
            message = String(format: "Đã thu %.1f giây. Nghe lại rồi đặt tên và bấm Lưu.", elapsed)
        } else {
            isError = true
            message = VieNeuVoiceRecorder.RecorderError.emptyRecording.errorDescription ?? "Bản thu không có dữ liệu."
        }
    }

    // MARK: - File

    private func acceptFile(_ url: URL) {
        isProbing = true
        message = ""
        Task {
            do {
                // Đọc ở luồng nền: file người dùng chọn có thể dài vài phút, giải mã trên main là đơ UI.
                let duration = try await Task.detached(priority: .userInitiated) {
                    try VieNeuAudioResampler.loadMono(url: url).duration
                }.value
                isProbing = false

                guard duration >= VieNeuVoiceCloner.minimumSampleSeconds else {
                    isError = true
                    message = String(
                        format: "File chỉ dài %.1f giây, cần ít nhất %.0f giây.",
                        duration, VieNeuVoiceCloner.minimumSampleSeconds
                    )
                    return
                }
                guard duration <= VieNeuVoiceCloner.maximumSampleSeconds else {
                    isError = true
                    message = String(
                        format: "File dài %.0f giây, chỉ dùng được tối đa %.0f giây. Hãy cắt bớt trước khi chọn.",
                        duration, VieNeuVoiceCloner.maximumSampleSeconds
                    )
                    return
                }

                stopPlayer()
                discardSample()
                sampleURL = url
                isError = false
                message = duration > VieNeuVoiceCloner.recommendedSampleSeconds
                    ? String(
                        format: "File dài %.1f giây — vẫn dùng được (chỉ 5 giây đầu tạo style), nhưng 3–8 giây cho kết quả tốt nhất.",
                        duration
                    )
                    : String(format: "Đã chọn file dài %.1f giây.", duration)
            } catch {
                isProbing = false
                isError = true
                message = error.localizedDescription
            }
        }
    }

    // MARK: - Phát / dọn

    private func playSample() {
        guard let sampleURL else { return }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: sampleURL)
            player = newPlayer
            isPlaying = true
            newPlayer.prepareToPlay()
            newPlayer.play()
        } catch {
            isError = true
            message = "Phát audio mẫu thất bại: \(error.localizedDescription)"
        }
    }

    private func stopPlayer() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    private func discardSample() {
        guard let url = sampleURL else { return }
        stopPlayer()
        try? FileManager.default.removeItem(at: url)
        sampleURL = nil
    }

    private func save() {
        guard let url = sampleURL else { return }
        if isRecording { stopRecording() }
        stopPlayer()
        // **Không** xoá file tạm ở đây: `VieNeuCustomVoiceStore.add` còn phải copy nó.
        onSave(name.trimmed, url)
    }

    private func cancel() {
        if isRecording {
            isRecording = false
            _ = recorder.stop()
        }
        stopPlayer()
        discardSample()
        onCancel()
    }
}
