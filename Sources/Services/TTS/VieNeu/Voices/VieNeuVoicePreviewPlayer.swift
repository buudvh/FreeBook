import AVFoundation
import Foundation
import Observation

/// **Thử giọng** VieNeu ở sheet chọn giọng (1.3.899): tổng hợp một câu mẫu bằng đúng engine của giọng (Nano / Turbo, cùng
/// đường tổng hợp với trình đọc) rồi phát. Khuôn nút ▶ cũ của màn "Giọng của tôi".
///
/// - Chặn khi truyện **đang phát** (`TTSManager.isPlaying`) — không chặn khi chỉ còn widget: Cài đặt TTS đã tạm dừng đọc,
///   chặn theo widget là lần nào cũng bị chặn. Trả `.blockedByReader` để View báo bằng toast (Service không gọi toast).
/// - Mỗi lúc một câu thử; bấm giọng khác ⇒ huỷ câu đang tổng hợp / dừng câu đang phát.
/// - Lỗi tổng hợp ⇒ `failureMessage` + `failureToken` tăng để View hiện toast.
@MainActor
@Observable
final class VieNeuVoicePreviewPlayer {
    static let shared = VieNeuVoicePreviewPlayer()

    /// Câu thử — cùng câu với màn thử giọng Nano để hai chỗ nghe ra giống nhau.
    static let sampleText = "Xin chào, đây là bản thử giọng đọc VieNeu-TTS."

    enum Phase: Equatable {
        case idle
        /// Đang tổng hợp câu thử của giọng có khoá này (`VieNeuVoiceSelection.key`).
        case preparing(String)
        case playing(String)
    }

    enum StartResult {
        case started
        case blockedByReader
    }

    enum PreviewError: LocalizedError {
        case engineUnavailable

        var errorDescription: String? { "Không dựng được engine VieNeu." }
    }

    private(set) var phase: Phase = .idle
    private(set) var failureMessage = ""
    private(set) var failureToken = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var didActivateSession = false
    @ObservationIgnored private var finishDelegate: FinishDelegate?

    private init() {
        finishDelegate = FinishDelegate { [weak self] in
            Task { @MainActor in self?.playbackDidFinish() }
        }
    }

    /// Giọng này đang tổng hợp hoặc đang phát câu thử.
    func isActive(_ key: String) -> Bool {
        switch phase {
        case .idle: return false
        case .preparing(let current), .playing(let current): return current == key
        }
    }

    @discardableResult
    func play(_ selection: VieNeuVoiceSelection) -> StartResult {
        guard !TTSManager.shared.isPlaying else { return .blockedByReader }
        stop()
        let key = selection.key
        phase = .preparing(key)
        AppLogger.shared.log("🎙️ [VieNeuPreview] Thử giọng \(key)")
        task = Task { [weak self] in
            do {
                let data = try await Self.synthesize(selection)
                guard let self, !Task.isCancelled, self.phase == .preparing(key) else { return }
                try self.startPlayback(data, key: key)
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled, self.phase == .preparing(key) else { return }
                self.phase = .idle
                self.failureMessage = "Thử giọng thất bại: \(error.localizedDescription)"
                self.failureToken += 1
                AppLogger.shared.log("❌ [VieNeuPreview] Thử giọng \(key) lỗi: \(error.localizedDescription)")
            }
        }
        return .started
    }

    /// Dừng câu đang tổng hợp / đang phát (sheet đóng, bấm ■, bắt đầu thu âm…).
    func stop() {
        task?.cancel()
        task = nil
        player?.stop()
        player = nil
        phase = .idle
        releaseSession()
    }

    // MARK: - Nội bộ

    /// Cùng engine với trình đọc (`synthesizeWithDuration`, ưu tiên `.demand`). Hàm `nonisolated` ⇒ chạy ngoài main.
    private nonisolated static func synthesize(_ selection: VieNeuVoiceSelection) async throws -> Data {
        switch selection.model {
        case .nano:
            guard let service = VieNeuTTSService.shared else { throw PreviewError.engineUnavailable }
            if !service.isPrepared { try await service.prepare(voice: selection.voiceId) }
            return try await service.synthesizeWithDuration(
                text: sampleText, voice: selection.voiceId, speed: 1.0, boundaryKind: .paragraphEnd, priority: .demand
            ).data
        case .turbo:
            guard let service = VieNeuTurboTTSService.shared else { throw PreviewError.engineUnavailable }
            return try await service.synthesizeWithDuration(
                text: sampleText, voice: selection.voiceId, speed: 1.0, boundaryKind: .paragraphEnd, priority: .demand
            ).data
        }
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

    private func playbackDidFinish() {
        guard case .playing = phase else { return }
        player = nil
        phase = .idle
        releaseSession()
    }

    /// `.playback` để câu thử nghe được cả khi gạt im lặng (như màn thử Turbo).
    private func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            didActivateSession = true
        } catch {
            AppLogger.shared.log("❌ [VieNeuPreview] Không giành được AVAudioSession: \(error.localizedDescription)")
        }
    }

    /// Trả phiên khi không ai khác đang phát (đọc truyện tiếp sẽ tự cấu hình lại phiên).
    private func releaseSession() {
        guard didActivateSession else { return }
        didActivateSession = false
        guard !TTSManager.shared.isPlaying, !VideoNativePlaybackFlag.isPlaying, !AudioPlaybackFlag.isPlaying else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// `AVAudioPlayerDelegate` cần `NSObject` — tách khỏi lớp `@Observable`.
    private final class FinishDelegate: NSObject, AVAudioPlayerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            onFinish()
        }
    }
}
