import Foundation

/// Bộ đệm nạp trước các chunk **đầu chương kế tiếp** (prefix) dùng chung cho NghiTTS,
/// Google TTS và Extension TTS.
///
/// Lý do tồn tại: cửa sổ prefetch đoạn văn bị chặn cứng ở biên chương
/// (`idx < paragraphs.count`), nên càng gần cuối chương buffer càng mỏng, và ngay sau
/// khi chuyển chương chỉ có đúng chunk 0 sẵn sàng. Bộ đệm này lấp phần thiếu đó bằng
/// các chunk đầu của chương kế, **trong đúng số slot mà cửa sổ hiện hành đang bỏ trống**.
///
/// Bất biến bắt buộc:
/// - Chỉ giữ chunk có index `>= 1`. Chunk 0 của chương kế vẫn do `TTSChapterPrefetcher`
///   sở hữu (nó có đường claim in-flight riêng khi chuyển chương).
/// - Số chunk giữ + đang bay không bao giờ vượt `capacity` mà caller truyền vào, nên tổng
///   payload audio trong RAM không vượt trần của cửa sổ đoạn văn hiện hành.
/// - Mọi dữ liệu gắn với đúng một `TTSPreparedNextChapterKey`. Key khác là reset toàn bộ;
///   `consume` chỉ trả dữ liệu khi key trùng tuyệt đối.
/// - Mọi tổng hợp đi qua đúng coordinator của engine ở **mức ưu tiên thấp nhất**
///   (`.optionalReserve` cho Nghi, `.nextChapter` cho remote), nên không bao giờ tranh
///   tài nguyên với đoạn đang phát hay slot N+1.
/// - Trạng thái lỗi theo index dùng lại `TTSManager.evaluateRefillError(maxAttempts: 2)`
///   nên phân loại lỗi retryable/non-retryable là **cùng một nguồn** với refill trong
///   chương; audio rỗng bị chặn ngay. Index đã block không được yêu cầu lại cho tới khi
///   `reset()` (đổi key/stop) xảy ra — prefix đầu cơ không bao giờ lặp vô hạn.
/// - Cấu hình của người dùng/extension được tôn trọng đầy đủ: số ký tự mỗi phân đoạn đã
///   nằm sẵn trong `key.chunkLength` (`max_length` với extension) — remote nhận DTO đã
///   chunk hoá từ `TTSBackgroundProcessor`, Nghi chunk lại bằng `NghiUtteranceSegmenter`
///   với đúng `key.chunkLength`; còn khoảng giãn giữa các request remote dùng
///   `prefetchDelayMs` với `offset = index`, y hệt cửa sổ đoạn văn trong chương.
@MainActor
internal final class TTSNextChapterPrefixCache {
    internal static let shared = TTSNextChapterPrefixCache()

    /// Một chunk đã tổng hợp, mang theo **đúng văn bản đã được đọc** để consumer xác minh
    /// index ↔ text trước khi nhồi vào cửa sổ đoạn văn. Đây là điều kiện làm cho highlight
    /// không thể lệch: highlight lấy `paragraphs[index].range`, nên audio ở `index` buộc
    /// phải là audio của đúng `paragraphs[index]`.
    internal struct PreparedChunk {
        internal let data: Data
        internal let finalText: String
    }

    private var activeKey: TTSPreparedNextChapterKey?
    private var chunks: [Int: PreparedChunk] = [:]
    private var durations: [Int: Double] = [:]
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var taskTokens: [Int: UInt64] = [:]
    private var failureStates: [Int: TTSManager.RefillFailureState] = [:]
    private var nextTaskToken: UInt64 = 0
    private var generation: UInt64 = 0

    private init() {}

    /// Số payload bộ đệm này đang chiếm dụng (đã xong + đang bay). Dùng để tính trần
    /// tổng payload audio, không phải để suy ra thời lượng.
    internal var reservedSlotCount: Int {
        chunks.count + tasks.count
    }

    /// Tổng thời lượng của chuỗi chunk **liên tục** bắt đầu từ `startIndex`; dừng ở khe
    /// trống đầu tiên. Trả `0` nếu key không trùng — cachedTime không bao giờ được cộng
    /// thời lượng của audio thuộc cấu hình khác.
    internal func contiguousDuration(matching key: TTSPreparedNextChapterKey, from startIndex: Int = 1) -> Double {
        guard activeKey == key else { return 0.0 }
        var total: Double = 0.0
        var index = startIndex
        while let duration = durations[index] {
            total += duration
            index += 1
        }
        return total
    }

    // MARK: - Yêu cầu nạp trước

    /// Nạp trước tối đa `capacity` chunk kế tiếp (index 1...capacity) của chương `key`.
    /// - Parameters:
    ///   - playbackParagraphs: mảng chunk **đã qua đúng phép chunk hoá của engine**
    ///     (caller phải truyền kết quả `playbackParagraphs(from:)`) để index khớp tuyệt đối
    ///     với `preloadedData` sau khi chuyển chương.
    ///   - capacity: số slot trống của cửa sổ hiện hành. `0` nghĩa là thu hồi hết.
    ///   - prefetchDelayMs: khoảng giãn giữa các request của engine remote
    ///     (`prefetchDelayMs` của Google / `extPrefetchDelay_<tool>` của extension).
    ///     Bỏ qua với NghiTTS vì engine offline không có cấu hình này.
    internal func request(
        key: TTSPreparedNextChapterKey,
        playbackParagraphs: [TTSParagraph],
        capacity: Int,
        prefetchDelayMs: Int,
        nghiService: (any LocalTTSSynthesizing)?,
        googleService: GoogleTTSService,
        extService: ExtTTSService,
        audioWorker: TTSAudioSynthesisWorker
    ) {
        guard key.tool != "system" else {
            reset()
            return
        }

        if activeKey != key {
            reset()
            activeKey = key
        }

        let boundedCapacity = max(0, capacity)
        trim(toCapacity: boundedCapacity)
        guard boundedCapacity > 0, playbackParagraphs.count > 1 else { return }

        let upperBound = min(playbackParagraphs.count, boundedCapacity + 1)
        guard upperBound > 1 else { return }

        for index in 1..<upperBound {
            guard chunks[index] == nil,
                  tasks[index] == nil,
                  failureStates[index]?.isBlocked != true else { continue }
            startSynthesis(
                key: key,
                index: index,
                paragraph: playbackParagraphs[index],
                prefetchDelayMs: prefetchDelayMs,
                nghiService: nghiService,
                googleService: googleService,
                extService: extService,
                audioWorker: audioWorker
            )
        }
    }

    // MARK: - Tiêu thụ & thu hồi

    /// Trả về các chunk đã sẵn sàng nếu key trùng tuyệt đối, rồi reset bộ đệm.
    /// Key khác (đổi giọng/pitch/chunkLength/cấu hình dịch…) trả về rỗng — không bao giờ
    /// dùng audio tổng hợp bằng cấu hình cũ.
    internal func consume(matching key: TTSPreparedNextChapterKey) -> [Int: PreparedChunk] {
        guard activeKey == key else {
            reset()
            return [:]
        }
        let ready = chunks
        reset()
        return ready
    }

    /// Hủy các tổng hợp đang bay nhưng **giữ** chunk đã xong và trạng thái lỗi.
    /// Dùng khi pause: không tiếp tục tổng hợp đầu cơ, nhưng không phí phần đã tổng hợp.
    /// `CancellationError` không được tính là một attempt (theo `evaluateRefillError`).
    internal func cancelPendingWork() {
        generation &+= 1
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
        taskTokens.removeAll()
    }

    /// Giải phóng toàn bộ (hủy task + xóa audio + xóa trạng thái lỗi + bỏ key).
    internal func reset() {
        generation &+= 1
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
        taskTokens.removeAll()
        failureStates.removeAll()
        chunks.removeAll()
        durations.removeAll()
        activeKey = nil
    }

    /// Thu hồi mọi index vượt quá `capacity` để tổng payload không bao giờ vượt trần.
    private func trim(toCapacity capacity: Int) {
        for index in Array(tasks.keys) where index > capacity {
            tasks[index]?.cancel()
            tasks.removeValue(forKey: index)
            taskTokens.removeValue(forKey: index)
        }
        for index in Array(chunks.keys) where index > capacity {
            chunks.removeValue(forKey: index)
            durations.removeValue(forKey: index)
        }
    }

    // MARK: - Tổng hợp một chunk

    private func startSynthesis(
        key: TTSPreparedNextChapterKey,
        index: Int,
        paragraph: TTSParagraph,
        prefetchDelayMs: Int,
        nghiService: (any LocalTTSSynthesizing)?,
        googleService: GoogleTTSService,
        extService: ExtTTSService,
        audioWorker: TTSAudioSynthesisWorker
    ) {
        let textToSpeak = TTSReplacementManager.shared.applyReplacements(to: paragraph.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSpeak.isEmpty else { return }

        if key.tool == "nghitts" && nghiService == nil { return }

        let synthesisKey = TTSSynthesisIdentity.computeKey(
            chapterURL: key.chapterUrl,
            chapterIndex: key.chapterIndex,
            paragraphIndex: index,
            finalText: textToSpeak,
            engine: key.tool,
            voice: key.selectedVoice,
            googlePitch: key.googlePitch,
            extensionFingerprint: key.extensionFingerprint
        )

        let expectedGeneration = generation
        let boundaryKind = paragraph.boundaryKind
        nextTaskToken &+= 1
        let token = nextTaskToken
        taskTokens[index] = token

        tasks[index] = Task { @MainActor [weak self] in
            let data: Data
            do {
                data = try await Self.synthesize(
                    key: key,
                    textToSpeak: textToSpeak,
                    boundaryKind: boundaryKind,
                    synthesisKey: synthesisKey,
                    offset: index,
                    prefetchDelayMs: prefetchDelayMs,
                    nghiService: nghiService,
                    googleService: googleService,
                    extService: extService,
                    audioWorker: audioWorker
                )
            } catch {
                self?.finishSynthesis(
                    index: index,
                    key: key,
                    token: token,
                    textToSpeak: textToSpeak,
                    data: nil,
                    error: error,
                    expectedGeneration: expectedGeneration
                )
                return
            }
            self?.finishSynthesis(
                index: index,
                key: key,
                token: token,
                textToSpeak: textToSpeak,
                data: data,
                error: nil,
                expectedGeneration: expectedGeneration
            )
        }
    }

    private nonisolated static func synthesize(
        key: TTSPreparedNextChapterKey,
        textToSpeak: String,
        boundaryKind: TTSBoundaryKind,
        synthesisKey: String,
        offset: Int,
        prefetchDelayMs: Int,
        nghiService: (any LocalTTSSynthesizing)?,
        googleService: GoogleTTSService,
        extService: ExtTTSService,
        audioWorker: TTSAudioSynthesisWorker
    ) async throws -> Data {
        if key.tool == "nghitts" {
            guard let nghiService else { throw CancellationError() }
            return try await nghiService.synthesize(
                text: textToSpeak,
                voice: key.selectedVoice,
                speed: 1.0,
                boundaryKind: boundaryKind,
                priority: .optionalReserve,
                requestID: UUID(),
                synthesisKey: synthesisKey
            )
        }

        if key.tool == "google" {
            let pitchToUse = key.googlePitch ?? 1.0
            return try await audioWorker.synthesizeParagraph(
                synthesisKey: synthesisKey,
                engine: "google",
                textLength: textToSpeak.count,
                priority: .nextChapter,
                offset: offset,
                prefetchDelayMs: prefetchDelayMs
            ) {
                try await googleService.synthesize(
                    text: textToSpeak,
                    voice: key.selectedVoice,
                    speed: 1.0,
                    pitch: pitchToUse
                )
            }
        }

        return try await audioWorker.synthesizeParagraph(
            synthesisKey: synthesisKey,
            engine: key.tool,
            textLength: textToSpeak.count,
            priority: .nextChapter,
            offset: offset,
            prefetchDelayMs: prefetchDelayMs
        ) {
            try await extService.synthesizeData(
                text: textToSpeak,
                voice: key.selectedVoice,
                localPath: key.extensionLocalPath,
                configJson: key.extensionConfigJson
            )
        }
    }

    /// Ghi kết quả về bộ đệm. Ba lớp guard: `generation` (thế hệ toàn cục),
    /// `activeKey` (đúng chương/cấu hình) và `token` (đúng task của index này — chống
    /// task cũ đã bị `trim` hủy xóa mất entry của task mới, tương ứng
    /// `removePrefetchTask(for:taskGen:)` của cửa sổ đoạn văn).
    private func finishSynthesis(
        index: Int,
        key: TTSPreparedNextChapterKey,
        token: UInt64,
        textToSpeak: String,
        data: Data?,
        error: Error?,
        expectedGeneration: UInt64
    ) {
        guard generation == expectedGeneration,
              activeKey == key,
              taskTokens[index] == token else { return }
        tasks.removeValue(forKey: index)
        taskTokens.removeValue(forKey: index)

        if let data, !data.isEmpty {
            chunks[index] = PreparedChunk(data: data, finalText: textToSpeak)
            durations[index] = WAVEncoder.duration(of: data)
            failureStates.removeValue(forKey: index)
            if AppLogger.shared.isLoggingEnabled {
                AppLogger.shared.log("[TTSPerf] NextChapterPrefixReady chapter=\(key.chapterIndex) engine=\(key.tool) index=\(index) prepared=\(chunks.count)")
            }
            return
        }

        // Audio rỗng luôn rỗng lại với cùng văn bản → chặn ngay, không thử lại.
        guard let error else {
            failureStates[index] = TTSManager.RefillFailureState(attempts: 1, isBlocked: true)
            logFailure(key: key, index: index, attempt: 1, reason: "empty_audio", action: "blocked_non_retryable")
            return
        }

        let attempts = failureStates[index]?.attempts ?? 0
        let evaluation = TTSManager.evaluateRefillError(error, currentAttempts: attempts, maxAttempts: 2)
        failureStates[index] = evaluation.newState

        switch evaluation.outcome {
        case .cancelled:
            return
        case .blocked(let reason, let action):
            logFailure(key: key, index: index, attempt: evaluation.newState.attempts, reason: reason, action: action)
        case .retryScheduled(let reason, let attempt):
            logFailure(key: key, index: index, attempt: attempt, reason: reason, action: "retry_on_next_window")
        case .success:
            return
        }
    }

    private func logFailure(
        key: TTSPreparedNextChapterKey,
        index: Int,
        attempt: Int,
        reason: String,
        action: String
    ) {
        guard AppLogger.shared.isLoggingEnabled else { return }
        AppLogger.shared.log("[TTSPerf] NextChapterPrefixFailure chapter=\(key.chapterIndex) engine=\(key.tool) index=\(index) attempt=\(attempt) reason=\(reason) action=\(action)")
    }
}
