import Foundation

/// **Giọng dự phòng** khi TTS online lỗi (1.3.945, anh Bửu duyệt) — xem `TTSOnlineFallbackSettings` / `TTSOnlineFallbackState`.
///
/// Thay engine **theo từng đoạn ở tầng tổng hợp**, không đổi `tool`: trình đọc vẫn là Google / tiện ích, đoạn vẫn chia theo
/// cài đặt của engine online (highlight giữ đúng, không dựng lại đoạn, không ghi đè `ttsTool`). Lúc đang dùng dự phòng,
/// đoạn đang đọc (`playWithOnlineFallbackIfNeeded`) và lượt nạp trước (nhánh trong `startPrefetchTask`) tổng hợp bằng engine
/// local dự phòng — gọi thẳng service, **không** qua hàng đợi `RemoteTTSSynthesisCoordinator` (lượt online treo tới hết giờ
/// không chặn dự phòng) — rồi phát qua `AVAudioPlayer` của đường remote ở tốc độ của engine dự phòng (`remotePlaybackRate`).
///
/// - Bật: tổng hợp online của đoạn đang đọc lỗi (sau lượt thử lại của coordinator — không thêm vòng thử lại nào ở đây), hoặc
///   máy đang mất mạng lúc cần tổng hợp đoạn đang đọc.
/// - Tắt: thử online ở nền thành công (`TTSManager+OnlineFallbackProbe`), phiên mới, hoặc giọng dự phòng cũng lỗi (dừng
///   đọc + báo như trước 1.3.945).
extension TTSManager {
    enum OnlineFallbackError: LocalizedError {
        case notConfigured
        case engineUnavailable(TTSOnlineFallbackSettings.Engine)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Chưa chọn giọng dự phòng"
            case .engineUnavailable(let engine): return "\(engine.title) chưa sẵn sàng trên máy"
            }
        }
    }

    // MARK: - Đoạn đang đọc

    /// Đầu `playGoogleTTS` / `playExtensionTTS`, sau nhánh đã có tiếng. Đang dùng dự phòng — hoặc chưa nhưng máy mất mạng mà
    /// có cài giọng dự phòng — ⇒ tổng hợp đoạn này bằng giọng dự phòng rồi phát; trả `true` (bên gọi thôi).
    func playWithOnlineFallbackIfNeeded(_ text: String, index: Int, playbackId: String, context: TTSPlaybackContext) -> Bool {
        if onlineFallback.isActive(session: sessionID), TTSOnlineFallbackSettings.engine == nil {
            // Người dùng chọn "Không dùng" giữa chừng ⇒ đọc online lại.
            onlineFallback.deactivate()
        }
        if !onlineFallback.isActive(session: sessionID) {
            guard let engine = TTSOnlineFallbackSettings.engine, TTSOnlineFallbackSettings.isOnlineTool(tool),
                  !TTSNetworkReachability.shared.isSatisfied else { return false }
            AppLogger.shared.log("[TTSFallback] Mất mạng ⇒ đọc bằng giọng dự phòng \(engine.title)")
            activateOnlineFallback(engine: engine, offline: true)
        }
        remotePlaybackTask?.cancel()
        remotePlaybackTaskGeneration &+= 1
        let generation = remotePlaybackTaskGeneration
        remotePlaybackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.remotePlaybackTaskGeneration == generation { self.remotePlaybackTask = nil }
            }
            do {
                let data = try await self.onlineFallbackAudio(index: index, text: text, priority: .demand)
                guard !Task.isCancelled, self.isContextValid(context), self.currentPlaybackId == playbackId else { return }
                self.playAudioData(data, context: context)
                self.updatePrefetchWindow()
            } catch is CancellationError {
                return
            } catch {
                guard self.currentPlaybackId == playbackId else { return }
                self.onlineFallbackFailed(error)
            }
        }
        return true
    }

    /// `catch` của `playGoogleTTS` / `playExtensionTTS`: tổng hợp online của đoạn đang đọc lỗi mà có giọng dự phòng ⇒ bật dự
    /// phòng rồi đọc lại đúng đoạn này; trả `true` (bên gọi không dừng đọc).
    func switchToOnlineFallback(after error: Error) -> Bool {
        guard isPlaying, let engine = TTSOnlineFallbackSettings.engine, TTSOnlineFallbackSettings.isOnlineTool(tool),
              !onlineFallback.isActive(session: sessionID) else { return false }
        AppLogger.shared.log(
            "❌ [TTSFallback] \(onlineFallbackOnlineName) lỗi (\(error.localizedDescription)) ⇒ đọc bằng giọng dự phòng \(engine.title)"
        )
        activateOnlineFallback(engine: engine, offline: false)
        speakCurrent()
        return true
    }

    private func activateOnlineFallback(engine: TTSOnlineFallbackSettings.Engine, offline: Bool) {
        onlineFallback.activate(session: sessionID)
        // Lượt nạp trước online đang chờ (có thể tới hết giờ) — bỏ để nạp lại bằng giọng dự phòng; tiếng đã có giữ nguyên.
        cancelRemotePrefetchTasks()
        let voice = Self.onlineFallbackVoiceTitle(for: engine)
        let message = offline
            ? "Mất mạng — đọc bằng giọng dự phòng \(voice)"
            : "\(onlineFallbackOnlineName) lỗi — đọc tiếp bằng giọng dự phòng \(voice)"
        TTSPresentationEventCenter.shared.send(.showToast(message: message, type: .info))
        // Mất mạng ⇒ chờ mạng có lại (`onlineFallbackNetworkChanged` thử ngay); lỗi ⇒ thử lại sau 15 s.
        startOnlineFallbackProbe(after: offline ? TTSOnlineFallbackState.maxProbeDelay : TTSOnlineFallbackState.firstProbeDelay)
    }

    /// Giọng dự phòng cũng lỗi ⇒ như trước 1.3.945: dừng đọc + báo.
    private func onlineFallbackFailed(_ error: Error) {
        AppLogger.shared.log("❌ [TTSFallback] Giọng dự phòng lỗi: \(error.localizedDescription) ⇒ tạm dừng đọc")
        onlineFallback.deactivate()
        currentPlaybackId = nil
        pause()
        TTSPresentationEventCenter.shared.send(.showToast(
            message: "Giọng dự phòng lỗi: \(error.localizedDescription). Tạm dừng đọc.",
            type: .error
        ))
    }

    // MARK: - Tổng hợp

    /// Tiếng của đoạn `index` bằng giọng dự phòng. Đoạn đang đọc và lượt nạp trước của cùng đoạn dùng chung một lượt.
    func onlineFallbackAudio(index: Int, text: String, priority: SynthesisPriority) async throws -> Data {
        guard let engine = TTSOnlineFallbackSettings.engine else { throw OnlineFallbackError.notConfigured }
        let key = onlineFallbackChunkKey(index)
        let task: Task<Data, Error>
        if let running = onlineFallback.task(for: key) {
            task = running
        } else {
            guard let service = onlineFallbackService(for: engine) else { throw OnlineFallbackError.engineUnavailable(engine) }
            let voice = engine == .vieneu ? Self.effectiveVieNeuVoice() : TTSOnlineFallbackSettings.nghiVoice
            let speed = Self.localSynthesisSpeed(forTool: engine.rawValue)
            let boundary = index >= 0 && index < paragraphs.count ? paragraphs[index].boundaryKind : .paragraphEnd
            task = Task {
                try await service.prepare(voice: voice)
                return try await service.synthesizeWithDuration(
                    text: text, voice: voice, speed: speed, boundaryKind: boundary, priority: priority, synthesisKey: nil
                ).data
            }
            onlineFallback.store(task, for: key)
        }
        do {
            let data = try await task.value
            onlineFallback.finish(task, for: key)
            onlineFallback.markFallback(key, engine: engine)
            return data
        } catch {
            onlineFallback.finish(task, for: key)
            throw error
        }
    }

    private func onlineFallbackService(for engine: TTSOnlineFallbackSettings.Engine) -> (any LocalTTSEngine)? {
        switch engine {
        case .nghitts:
            return nghiTTSService
        case .vieneu:
            if VieNeuModelChoice.current == .turbo { return VieNeuTurboTTSService.shared }
            return VieNeuTTSService.shared
        }
    }

    // MARK: - Phát + badge

    func onlineFallbackChunkKey(_ index: Int) -> TTSOnlineFallbackState.ChunkKey {
        TTSOnlineFallbackState.ChunkKey(sessionID: sessionID, chapterIndex: playingChapterIndex, index: index)
    }

    /// Engine dự phòng đã tạo tiếng của đoạn `index` (chương đang đọc); `nil` ⇒ tiếng online.
    func onlineFallbackEngine(forChunk index: Int) -> TTSOnlineFallbackSettings.Engine? {
        onlineFallback.engine(of: onlineFallbackChunkKey(index))
    }

    /// Đoạn `index` vừa có tiếng online (đoạn đang đọc / nạp trước / lượt thử) ⇒ thôi coi là đoạn dự phòng.
    func noteOnlineAudio(index: Int) {
        onlineFallback.markOnline(onlineFallbackChunkKey(index))
    }

    /// Tốc độ `AVAudioPlayer` của đường remote: đoạn dự phòng phát theo tốc độ của engine dự phòng.
    func remotePlaybackRate(for index: Int) -> Double {
        guard let engine = onlineFallbackEngine(forChunk: index) else { return speed }
        return TTSOnlineFallbackSettings.playbackSpeed(for: engine)
    }

    /// Tên trình đọc online cho toast / log: "Google TTS" hoặc tên tiện ích.
    var onlineFallbackOnlineName: String {
        if tool == "google" { return "Google TTS" }
        return ExtensionLibraryRepository.snapshot(packageId: tool)?.name ?? "TTS tiện ích"
    }

    /// "VieNeu · Mai Anh" / "NghiTTS · Ngọc Huyền (mới)" — giọng engine dự phòng sẽ đọc.
    static func onlineFallbackVoiceTitle(for engine: TTSOnlineFallbackSettings.Engine) -> String {
        switch engine {
        case .nghitts:
            return "\(engine.title) · \(TTSOnlineFallbackSettings.nghiVoice)"
        case .vieneu:
            let selection = VieNeuVoiceSelection(model: VieNeuModelChoice.current, voiceId: effectiveVieNeuVoice())
            let name = VieNeuVoiceDirectory.shared.entry(for: selection)?.name ?? selection.voiceId
            return "\(engine.title) · \(name)"
        }
    }
}
