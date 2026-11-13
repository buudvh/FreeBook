import AVFoundation
import Foundation
import Observation

/// **Thử giọng** ở sheet chọn giọng chung của Siri / NghiTTS / Google / tiện ích TTS: đọc một câu mẫu bằng đúng đường
/// tổng hợp của trình đọc rồi phát. Khuôn `VieNeuVoicePreviewPlayer` (VieNeu giữ player riêng của nó).
///
/// - Siri: `AVSpeechSynthesizer` riêng của player với giọng được chọn.
/// - NghiTTS: `TTSManager.nghiTTSService` — cùng `PiperSynthesisCoordinator`, **không** dựng ORT session thứ hai. Piper chỉ
///   giữ một session ⇒ thử giọng khác giọng trình đọc thì `finishSession()` nạp sẵn lại giọng của trình đọc.
/// - Google: `GoogleTTSService.shared` (key cá nhân / key hệ thống như trình đọc). Tiện ích: `TTSManager.extService`
///   (cùng runtime JS dùng lâu dài của trình đọc), đường dẫn + cấu hình lấy từ bản ghi tiện ích.
/// - Chặn khi truyện **đang phát** (`TTSManager.isPlaying`) — trả `.blockedByReader` để View báo bằng toast (Service không
///   gọi toast). Mỗi lúc một câu thử; bấm giọng khác ⇒ huỷ câu đang tổng hợp / dừng câu đang phát.
/// - Lỗi tổng hợp ⇒ `failureMessage` + `failureToken` tăng để View hiện toast.
@MainActor
@Observable
final class TTSVoicePreviewPlayer {
    static let shared = TTSVoicePreviewPlayer()

    /// Câu thử — một câu chung cho mọi giọng để nghe so được với nhau.
    nonisolated static let sampleText = "Xin chào, đây là giọng đọc thử."

    enum Request: Sendable {
        case siri(identifier: String)
        /// Id file model (`Voice.id`) — `PiperTTSService` tự đổi sang id ASCII, id đã là ASCII thì giữ nguyên.
        case nghi(voiceId: String)
        case google(voiceId: String)
        case ext(localPath: String, configJson: String, voiceId: String)
    }

    enum Phase: Equatable {
        case idle
        /// Đang tổng hợp câu thử của giọng có khoá này.
        case preparing(String)
        case playing(String)
    }

    enum StartResult {
        case started
        case blockedByReader
    }

    enum PreviewError: LocalizedError {
        case nghiUnavailable

        var errorDescription: String? { "Chưa khởi tạo được engine NghiTTS." }
    }

    private(set) var phase: Phase = .idle
    private(set) var failureMessage = ""
    private(set) var failureToken = 0
    /// Giọng NghiTTS của câu thử gần nhất trong phiên sheet — `finishSession()` so với giọng trình đọc.
    @ObservationIgnored private var lastNghiVoiceId: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var synthesizer: AVSpeechSynthesizer?
    @ObservationIgnored private var didActivateSession = false
    @ObservationIgnored private var finishDelegate: FinishDelegate?

    private init() {
        finishDelegate = FinishDelegate { [weak self] source in
            Task { @MainActor in self?.playbackDidFinish(source: source) }
        }
    }

    /// Giọng có khoá này đang tổng hợp hoặc đang phát câu thử.
    func isActive(_ key: String) -> Bool {
        switch phase {
        case .idle: return false
        case .preparing(let current), .playing(let current): return current == key
        }
    }

    @discardableResult
    func play(_ request: Request, key: String) -> StartResult {
        guard !TTSManager.shared.isPlaying else { return .blockedByReader }
        stop()
        AppLogger.shared.log("🎙️ [VoicePreview] Thử giọng \(key)")
        let operation: @Sendable () async throws -> Data
        switch request {
        case .siri(let identifier):
            speakWithSiri(identifier: identifier, key: key)
            return .started
        case .nghi(let voiceId):
            lastNghiVoiceId = voiceId
            guard let service = TTSManager.shared.nghiTTSService else {
                report(PreviewError.nghiUnavailable, key: key)
                return .started
            }
            operation = { try await service.synthesize(text: Self.sampleText, voice: voiceId, speed: 1.0) }
        case .google(let voiceId):
            let service = GoogleTTSService.shared
            operation = { try await service.synthesize(text: Self.sampleText, voice: voiceId, speed: 1.0, pitch: 1.0) }
        case .ext(let localPath, let configJson, let voiceId):
            let service = TTSManager.shared.extService
            operation = {
                try await service.synthesizeData(
                    text: Self.sampleText, voice: voiceId, localPath: localPath, configJson: configJson
                )
            }
        }
        phase = .preparing(key)
        task = Task { [weak self] in
            do {
                let data = try await operation()
                guard let self, !Task.isCancelled, self.phase == .preparing(key) else { return }
                try self.startPlayback(data, key: key)
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled, self.phase == .preparing(key) else { return }
                self.report(error, key: key)
            }
        }
        return .started
    }

    /// Dừng câu đang tổng hợp / đang phát (sheet đóng, bấm ■, bắt đầu tải…).
    func stop() {
        task?.cancel()
        task = nil
        player?.stop()
        player = nil
        if let synthesizer {
            // Gỡ delegate trước: `stopSpeaking` báo `didCancel`, không gỡ thì câu thử kế tiếp bị kết thúc oan.
            synthesizer.delegate = nil
            synthesizer.stopSpeaking(at: .immediate)
        }
        synthesizer = nil
        phase = .idle
        releaseSession()
    }

    /// Sheet chọn giọng đóng: dừng câu thử. Đã thử một giọng NghiTTS **khác** giọng trình đọc (Piper chỉ giữ một session,
    /// câu thử đã thay model) ⇒ nạp sẵn lại giọng trình đọc để đoạn đọc tiếp không phải chờ nạp model.
    func finishSession() {
        stop()
        defer { lastNghiVoiceId = nil }
        let tts = TTSManager.shared
        guard let previewed = lastNghiVoiceId, tts.tool == "nghitts",
              previewed.toASCIIID != tts.selectedVoice.toASCIIID else { return }
        AppLogger.shared.log("🎙️ [VoicePreview] Đã thử giọng NghiTTS \(previewed) — nạp lại giọng của trình đọc")
        tts.scheduleNghiWarmUp()
    }

    // MARK: - Nội bộ

    private func speakWithSiri(identifier: String, key: String) {
        activateSession()
        let newSynthesizer = AVSpeechSynthesizer()
        newSynthesizer.delegate = finishDelegate
        let utterance = AVSpeechUtterance(string: Self.sampleText)
        utterance.voice = AVSpeechSynthesisVoice(identifier: identifier) ?? AVSpeechSynthesisVoice(language: "vi-VN")
        synthesizer = newSynthesizer
        phase = .playing(key)
        newSynthesizer.speak(utterance)
    }

    private func startPlayback(_ data: Data, key: String) throws {
        activateSession()
        let newPlayer = try AVAudioPlayer(data: data)
        newPlayer.delegate = finishDelegate
        newPlayer.prepareToPlay()
        newPlayer.play()
        player = newPlayer
        phase = .playing(key)
    }

    private func report(_ error: Error, key: String) {
        phase = .idle
        releaseSession()
        failureMessage = "Thử giọng thất bại: \(error.localizedDescription)"
        failureToken += 1
        AppLogger.shared.log("❌ [VoicePreview] Thử giọng \(key) lỗi: \(error.localizedDescription)")
    }

    /// Chỉ kết thúc khi đúng player / synthesizer đang giữ câu thử báo xong — báo trễ của câu cũ thì bỏ qua.
    private func playbackDidFinish(source: ObjectIdentifier) {
        guard case .playing = phase else { return }
        let current = player.map { ObjectIdentifier($0) } ?? synthesizer.map { ObjectIdentifier($0) }
        guard current == source else { return }
        player = nil
        synthesizer = nil
        phase = .idle
        releaseSession()
    }

    /// `.playback` để câu thử nghe được cả khi gạt im lặng.
    private func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            didActivateSession = true
        } catch {
            AppLogger.shared.log("❌ [VoicePreview] Không giành được AVAudioSession: \(error.localizedDescription)")
        }
    }

    /// Trả phiên khi **không ai khác giữ** nó — cùng luật `VieNeuVoicePreviewPlayer.releaseSession`: TTS đang có phiên (kể
    /// cả chỉ tạm dừng vì mở Cài đặt TTS) là chủ phiên, tắt ở đây là đóng Cài đặt xong mất tiếng / mất màn khoá.
    private func releaseSession() {
        guard didActivateSession else { return }
        didActivateSession = false
        let tts = TTSManager.shared
        guard !tts.isPlaying, tts.playingBookId.isEmpty, !tts.isAudioSessionConfigured,
              !VideoNativePlaybackFlag.isPlaying, !AudioPlaybackFlag.isPlaying else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Delegate của `AVAudioPlayer` / `AVSpeechSynthesizer` cần `NSObject` — tách khỏi lớp `@Observable`. Báo kèm danh
    /// tính nguồn để player bỏ qua báo trễ của câu thử cũ.
    private final class FinishDelegate: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
        private let onFinish: (ObjectIdentifier) -> Void

        init(onFinish: @escaping (ObjectIdentifier) -> Void) {
            self.onFinish = onFinish
        }

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            onFinish(ObjectIdentifier(player))
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            onFinish(ObjectIdentifier(synthesizer))
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            onFinish(ObjectIdentifier(synthesizer))
        }
    }
}
