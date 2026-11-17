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
        guard isPlaying, let engine = TTSOnlineFallbackSettings.engine, TTSOnlineFallbackSettings.isOnlineTool(tool) else { return false }
        // Đã bật dự phòng rồi (ví dụ do lượt nạp trước hụt timeout — 1.3.953) mà lượt đang đọc vẫn lỗi ⇒ đọc lại
        // đoạn này bằng giọng dự phòng, **không** dừng đọc.
        if onlineFallback.isActive(session: sessionID) {
            AppLogger.shared.log(
                "❌ [TTSFallback] \(onlineFallbackOnlineName) lỗi (\(error.localizedDescription)) ⇒ đọc lại bằng giọng dự phòng \(engine.title)"
            )
            speakCurrent()
            return true
        }
        AppLogger.shared.log(
            "❌ [TTSFallback] \(onlineFallbackOnlineName) lỗi (\(error.localizedDescription)) ⇒ đọc bằng giọng dự phòng \(engine.title)"
        )
        activateOnlineFallback(engine: engine, offline: false)
        speakCurrent()
        return true
    }

    /// Bật giọng dự phòng cho phiên hiện tại. Bỏ các lượt nạp trước online đang chờ (có thể tới hết giờ) để nạp lại bằng
    /// giọng dự phòng; tiếng đã nạp giữ nguyên. Từ 1.3.960 mọi đường bật đều bỏ: chỉ bật khi online đã hết lượt thử hoặc
    /// mất mạng, nên các lượt online đang chờ gần như chắc cũng hụt (1.3.953 giữ chúng vì một lần hụt 3 s chưa đủ chắc).
    func activateOnlineFallback(engine: TTSOnlineFallbackSettings.Engine, offline: Bool, message: String? = nil) {
        onlineFallback.activate(session: sessionID)
        cancelRemotePrefetchTasks()
        let voice = Self.onlineFallbackVoiceTitle(for: engine)
        let toastMessage = message ?? (offline
            ? "Mất mạng — đọc bằng giọng dự phòng \(voice)"
            : "\(onlineFallbackOnlineName) lỗi — đọc tiếp bằng giọng dự phòng \(voice)")
        TTSPresentationEventCenter.shared.send(.showToast(message: toastMessage, type: .info))
        // Mất mạng ⇒ chờ mạng có lại (`onlineFallbackNetworkChanged` thử ngay); lỗi ⇒ thử lại sau 15 s.
        startOnlineFallbackProbe(after: offline ? TTSOnlineFallbackState.maxProbeDelay : TTSOnlineFallbackState.firstProbeDelay)
    }

    /// Một lượt online vừa hụt mà còn lượt thử (`RemoteTTSAttemptPolicy.run`) ⇒ nạp sẵn engine dự phòng ở nền, mỗi phiên
    /// một lần (1.3.962). Log build 1288: lượt nạp trước hụt lần đầu 7,4 s trước khi phải chuyển, nhưng VieNeu chỉ được nạp
    /// lúc chuyển ⇒ đoạn dự phòng đầu tiên tổng hợp nguội 1,9 s (RTF 0,31; các đoạn sau 0,12), khoảng lặng 2,4 s. Không nạp
    /// sẵn ngay khi bắt đầu đọc: engine dự phòng (VieNeu ~280 MB) chỉ nên chiếm RAM khi online đã có dấu hiệu trục trặc.
    func prewarmOnlineFallback() {
        guard isPlaying, let engine = TTSOnlineFallbackSettings.engine, TTSOnlineFallbackSettings.isOnlineTool(tool),
              !onlineFallback.isActive(session: sessionID),
              let service = onlineFallbackService(for: engine),
              onlineFallback.claimPrewarm(session: sessionID) else { return }
        let voice = engine == .vieneu ? Self.effectiveVieNeuVoice() : TTSOnlineFallbackSettings.nghiVoice
        AppLogger.shared.log("[TTSFallback] \(onlineFallbackOnlineName) vừa hụt một lượt ⇒ nạp sẵn giọng dự phòng \(engine.title)")
        Task(priority: .utility) {
            do {
                try await service.prepare(voice: voice)
            } catch {
                AppLogger.shared.log("❌ [TTSFallback] Nạp sẵn giọng dự phòng lỗi: \(error.localizedDescription)")
            }
        }
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
        let voice = engine == .vieneu ? Self.effectiveVieNeuVoice() : TTSOnlineFallbackSettings.nghiVoice
        let speed = Self.localSynthesisSpeed(forTool: engine.rawValue)
        let boundary = index >= 0 && index < paragraphs.count ? paragraphs[index].boundaryKind : .paragraphEnd
        let synthesisKey = Self.onlineFallbackSynthesisKey(
            engine: engine, voice: voice, speed: speed, boundary: boundary, text: text
        )
        let isDemand = priority == .demand
        let task: Task<Data, Error>
        if let running = onlineFallback.task(for: key), !running.isCancelled, !isDemand || onlineFallback.hasStarted(key) {
            task = running
            if isDemand {
                // Đoạn đang đọc dùng chung lượt nạp trước đã rời hàng chờ ⇒ nâng mức ưu tiên của nó trong hàng đợi tổng hợp.
                Task { await PiperSynthesisCoordinator.shared.promote(synthesisKey: synthesisKey, to: .demand) }
            }
        } else {
            guard let service = onlineFallbackService(for: engine) else { throw OnlineFallbackError.engineUnavailable(engine) }
            // Đoạn đang đọc mà lượt nạp trước của nó còn xếp hàng sau lượt khác ⇒ bỏ lượt đó, tạo lượt mới đi thẳng.
            onlineFallback.task(for: key)?.cancel()
            let state = onlineFallback
            // Lượt nạp trước nối đuôi lượt nạp trước tạo ngay trước nó (1.3.957). Mỗi lượt phải qua `prepare` (nhiều điểm chờ)
            // rồi mới vào hàng đợi tổng hợp, nên để tự do thì lượt nào tới trước là ngẫu nhiên — và hàng đợi không ngắt lượt
            // đang chạy. Log build 1283: đoạn 3 → 2 → 1; build 1285: đoạn 23 chạy trước đoạn 22 nên đoạn 22 trễ 0,46 s.
            let previous = isDemand ? nil : state.prefetchTail
            task = Task {
                if let previous { _ = try? await previous.value }
                try Task.checkCancellation()
                state.markStarted(key)
                try await service.prepare(voice: voice)
                return try await service.synthesizeWithDuration(
                    text: text, voice: voice, speed: speed, boundaryKind: boundary, priority: priority,
                    synthesisKey: synthesisKey
                ).data
            }
            onlineFallback.store(task, for: key, isPrefetch: !isDemand)
        }
        // Người chờ bị huỷ mà không còn ai chờ ⇒ huỷ luôn lượt tổng hợp (1.3.960): `task.value` không tự truyền huỷ xuống.
        let waiter = UUID()
        let state = onlineFallback
        state.addWaiter(waiter, for: key)
        do {
            let data = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                Task { @MainActor in state.removeWaiter(waiter, for: key, task: task, cancelIfIdle: true) }
            }
            state.removeWaiter(waiter, for: key, task: task, cancelIfIdle: false)
            state.finish(task, for: key)
            state.markFallback(key, engine: engine)
            return data
        } catch {
            state.removeWaiter(waiter, for: key, task: task, cancelIfIdle: false)
            state.finish(task, for: key)
            throw error
        }
    }

    /// Khoá tổng hợp của một đoạn dự phòng trong hàng đợi `PiperSynthesisCoordinator` — có khoá thì đoạn đang đọc mới nâng
    /// được mức ưu tiên của lượt nạp trước đang chờ (`promote`). Cùng engine + giọng + tốc độ + ranh giới + chữ ⇒ cùng tiếng,
    /// nên hai đoạn trùng khoá gộp chung một lượt là đúng. Băm SHA-256 như mọi khoá tổng hợp khác (`TTSSynthesisIdentity`,
    /// 1.3.960 — bản băm djb2 tự viết trước đó trùng khoá thì hai đoạn khác nhau bị gộp, phát nhầm tiếng).
    private static func onlineFallbackSynthesisKey(
        engine: TTSOnlineFallbackSettings.Engine,
        voice: String,
        speed: Double,
        boundary: TTSBoundaryKind,
        text: String
    ) -> String {
        let digest = TTSSynthesisIdentity.computeKey(
            chapterURL: "online-fallback", chapterIndex: -1, paragraphIndex: -1, finalText: text,
            engine: engine.rawValue, voice: "\(voice)|boundary=\(boundary.rawValue)", synthesisSpeed: speed
        )
        return "fallback-\(digest)"
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

    /// Ghi tiếng **online** của đoạn `index` (chương đang đọc) vào bộ đệm nạp trước, luôn kèm xoá dấu "dự phòng" (1.3.960:
    /// đường nạp gộp Google từng quên xoá dấu ⇒ đoạn online phát theo tốc độ của giọng dự phòng và hiện badge "Dự phòng").
    /// Tiếng đầu chương kế / prefix chương ghi ngay sau `forgetChunks` nên không cần.
    func storeOnlineAudio(_ data: Data, at index: Int) {
        preloadedData[index] = data
        noteOnlineAudio(index: index)
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
