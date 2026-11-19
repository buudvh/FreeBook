import Foundation

/// Tự quay lại giọng online (1.3.945, anh Bửu: "tự quay lại khi giọng online hết lỗi").
///
/// Lúc đang đọc dự phòng, một vòng nền thử TTS online: chờ 15 s → 30 s → 1 phút → tối đa 2 phút giữa các lượt; mất mạng thì
/// không thử (có mạng lại ⇒ thử ngay); đang tạm dừng thì chờ; phiên tắt / đổi ⇒ thôi. Mỗi lượt tổng hợp online **một** đoạn
/// sắp đọc qua `RemoteTTSSynthesisCoordinator` ở mức thấp nhất, một lần thử (1.3.960 — trước đó gọi thẳng service nên chạy
/// chồng lượt tiện ích khác trên cùng runtime JS). Được ⇒ giữ tiếng online cho đoạn ấy, tắt dự phòng: các đoạn dự phòng đã
/// nạp xong phát nốt, lượt dự phòng chưa xong bị huỷ (1.3.962), phần còn thiếu nạp online.
extension TTSManager {
    func startOnlineFallbackProbe(after delay: TimeInterval) {
        onlineFallback.probeTask?.cancel()
        let session = sessionID
        onlineFallback.probeTask = Task { @MainActor [weak self] in
            var wait = delay
            var nextWait = TTSOnlineFallbackState.firstProbeDelay
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled, let self, self.onlineFallback.isActive(session: session) else { return }
                guard self.showFloatingWidget, self.sessionID == session else {
                    self.onlineFallback.deactivate()
                    return
                }
                guard self.isPlaying else {
                    wait = 10
                    continue
                }
                guard TTSNetworkReachability.shared.isSatisfied else {
                    wait = TTSOnlineFallbackState.maxProbeDelay
                    continue
                }
                switch await self.probeOnlineOnce(session: session) {
                case .recovered:
                    guard self.onlineFallback.isActive(session: session) else { return }
                    self.returnToOnline()
                    return
                case .noTarget:
                    wait = 10
                case .failed:
                    wait = nextWait
                    nextWait = min(nextWait * 2, TTSOnlineFallbackState.maxProbeDelay)
                }
            }
        }
    }

    /// `TTSNetworkReachability` báo mạng đổi. Có mạng lại lúc đang đọc dự phòng ⇒ thử online ngay.
    func onlineFallbackNetworkChanged(isSatisfied: Bool) {
        guard isSatisfied, onlineFallback.isActive(session: sessionID) else { return }
        startOnlineFallbackProbe(after: 1)
    }

    private enum OnlineProbeResult {
        case recovered
        case failed
        case noTarget
    }

    private func probeOnlineOnce(session: UUID) async -> OnlineProbeResult {
        guard let index = onlineProbeTargetIndex() else { return .noTarget }
        let rawText = paragraphs[index].text
        let text = TTSReplacementManager.shared.applyReplacements(to: rawText, bookId: playingBookId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .noTarget }
        let chapter = playingChapterIndex
        let engineTool = tool
        let voice = selectedVoice
        let pitchToUse = pitch
        let localPath = extensionLocalPath
        let configJson = extensionConfigJson
        let google = googleService
        let ext = extService
        let name = onlineFallbackOnlineName
        AppLogger.shared.log("[TTSFallback] Thử lại \(name) (chương \(chapter), đoạn \(index))")
        do {
            // Qua hàng đợi chung như mọi lượt TTS online (1.3.960): runtime JS của tiện ích chỉ chịu một lượt mỗi lúc — gọi
            // thẳng service thì lượt thử chạy chồng lượt khác và hết giờ là huỷ luôn lượt kia. Mức `.nextChapter` = thấp
            // nhất, một lần thử, timeout theo cài đặt (`RemoteTTSAttemptPolicy`).
            let data = try await RemoteTTSSynthesisCoordinator.shared.synthesize(
                key: "fallback-probe|\(UUID().uuidString)", engine: engineTool, textLength: text.count, priority: .nextChapter
            ) {
                if engineTool == "google" {
                    return try await google.synthesize(text: text, voice: voice, speed: 1.0, pitch: pitchToUse)
                }
                return try await ext.synthesizeData(text: text, voice: voice, localPath: localPath, configJson: configJson)
            }
            guard !data.isEmpty else { return .failed }
            // Online chạy lại; tiếng chỉ giữ khi vẫn đúng phiên / chương / đoạn còn thiếu hoặc đang là tiếng dự phòng.
            // So chữ: dịch lại khi đang nghe (`TTSManager+RetranslationSplice`) có thể đã thay chunk ở chỉ số này.
            if sessionID == session, playingChapterIndex == chapter, index > currentParagraphIndex, index < paragraphs.count,
               paragraphs[index].text == rawText {
                storeOnlineAudio(data, at: index)
            }
            return .recovered
        } catch is CancellationError {
            return .noTarget
        } catch {
            AppLogger.shared.log("[TTSFallback] \(name) vẫn lỗi: \(error.localizedDescription)")
            return .failed
        }
    }

    /// Đoạn để thử: đoạn xa nhất trong cửa sổ nạp trước (đoạn dự phòng gần hơn vẫn phát nốt). Hết chương ⇒ không có.
    private func onlineProbeTargetIndex() -> Int? {
        let count = max(1, min(10, currentPrefetchCount))
        let target = min(currentParagraphIndex + count, paragraphs.count - 1)
        return target > currentParagraphIndex ? target : nil
    }

    /// Online chạy lại ⇒ tắt dự phòng. Đoạn dự phòng đã nạp **xong** phát nốt; lượt nạp trước dự phòng **chưa xong** bị huỷ
    /// (lượt tổng hợp của nó tự huỷ khi không còn ai chờ) rồi cửa sổ nạp lại bằng online (1.3.962). Log build 1288: lượt
    /// dự phòng của đoạn 66 bắt đầu 41 ms trước khi online chạy lại, chạy nốt 2,4 s rồi vẫn được phát bằng giọng dự phòng,
    /// trong khi online chỉ mất 0,3–0,7 s. Cả cửa sổ lúc này chỉ có lượt dự phòng: lượt online đã bị bỏ khi bật dự phòng.
    private func returnToOnline() {
        let pendingFallback = prefetchTasks.count
        AppLogger.shared.log(
            "[TTSFallback] \(onlineFallbackOnlineName) hoạt động lại ⇒ quay lại giọng online (bỏ \(pendingFallback) lượt nạp trước dự phòng chưa xong)"
        )
        onlineFallback.deactivate()
        cancelRemotePrefetchTasks()
        TTSPresentationEventCenter.shared.send(.showToast(
            message: "\(onlineFallbackOnlineName) hoạt động lại — đọc tiếp bằng giọng online",
            type: .success
        ))
        updatePrefetchWindow()
    }
}
