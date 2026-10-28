import Foundation

/// Vòng gửi lượt của quét tên riêng nhiều chương — tách khỏi file gốc (sát trần 400 dòng) theo mẫu `X+Feature.swift`
/// (1.3.602), kèm luật gộp tên.
extension AINameExtractionBatchProcessor {
    /// Nghỉ trước khi gửi lại lượt trả về rỗng với provider API (Gemini Web nghỉ `geminiWebTurnPause`).
    private static let emptyTurnRetryPause: UInt64 = 1_000_000_000

    /// Vòng gửi từng lượt — dùng chung cho vòng quét chính, vòng tự thử lại ở cuối và nút "Thử lại k lượt lỗi"
    /// (1.3.527): cùng prompt, cùng cuộc chat của phiên, cùng timeout, cùng nghỉ 2 s, cùng cách đếm lỗi và huỷ.
    /// `seedNames`: danh sách đã có — tên mới gộp vào đó nên danh sách báo qua `onProgress` luôn đầy đủ.
    ///
    /// 1.3.602: lượt trả về không có name (Gemini Web hay từ chối lọc tên) được gửi lại một lần
    /// (`extractTurnRetryingEmpty`), vẫn rỗng thì tính là **lượt lỗi** như lỗi lẻ — vào vòng tự thử lại / nút thử lại và
    /// chặn điểm tiếp nối. 1.3.603: vẫn rỗng nhưng AI đã trả lời đúng "Không có name" (ở lần đầu hoặc lần gửi lại) thì là
    /// **lượt hợp lệ** — không tính lỗi, không chặn điểm tiếp nối. Mỗi lượt xong mà không bị huỷ được ghi vào `resume`;
    /// báo sau lượt kèm điểm tiếp nối mới.
    ///
    /// 1.3.612: provider đọc **mỗi lượt** từ `providerSwitch` — Chế độ AI của Google bị giới hạn thì lần quét có thể chuyển
    /// sang Gemini Web giữa chừng (`+RateLimit.swift`); nghỉ 2 s giữa lượt theo provider đang dùng.
    ///
    /// Trước khi gửi mỗi lượt, tiến độ mang các chương của lượt đó và tên đã dịch theo `chapterTitleStyle` (`nil` = tên
    /// gốc) — dịch ở đây, một lần mỗi lượt, ngoài main thread (`markSending`).
    func runTurns(
        _ turns: [AINameScanFailedBatch],
        seedNames: [AIExtractedName],
        providerSwitch: GoogleAccountRotation,
        promptOverride: String?,
        conversationId: UUID?,
        isRetry: Bool,
        chapterCount: Int?,
        resume: AINameScanResumeTracker?,
        chapterTitleStyle: AINameScanChapterTitleStyle?,
        onProgress: @escaping @Sendable (AINameScanProgress, [AIExtractedName]?) -> Void
    ) async throws -> ScanOutcome {
        var progress = AINameScanProgress(
            totalBatches: turns.count,
            chapterCount: chapterCount,
            isRetry: isRetry,
            preparedChapters: chapterCount ?? 0,
            resumeChapterIndex: resume?.resumeChapterIndex,
            switchedProviderName: providerSwitch.switchedProviderName
        )
        var aggregatedNames: [String: AIExtractedName] = [:]
        Self.aggregate(seedNames, into: &aggregatedNames)
        var failed: [AINameScanFailedBatch] = []

        for (position, turn) in turns.enumerated() {
            if Task.isCancelled { break }
            let turnLabel = isRetry ? "\(turn.turnLabel), thử lại" : turn.turnLabel
            let characterLimit = Self.turnCharacterLimit(for: providerSwitch.config)
            progress.sendingBatch = position + 1
            Self.markSending(turn, style: chapterTitleStyle, into: &progress)
            onProgress(progress, nil)
            AppLogger.shared.log("🤖 [AI] Quét tên riêng: gửi \(turnLabel) (\(min(turn.text.count, characterLimit)) ký tự, chat phiên=\(conversationId != nil))")

            var succeeded = false
            do {
                let reply = try await extractTurnHandlingRateLimit(
                    turn,
                    turnLabel: turnLabel,
                    providerSwitch: providerSwitch,
                    promptOverride: promptOverride,
                    conversationId: conversationId,
                    progress: &progress,
                    onProgress: onProgress
                )
                if !reply.names.isEmpty {
                    Self.aggregate(reply.names, into: &aggregatedNames)
                    succeeded = true
                } else if reply.saidNoNames {
                    succeeded = true
                    AppLogger.shared.log("🤖 [AI] Quét tên riêng: \(turnLabel) AI trả lời \"Không có name\" sau khi gửi lại — coi là lượt hợp lệ")
                } else {
                    progress.failedBatches += 1
                    failed.append(turn)
                    AppLogger.shared.log("❌ 🤖 [AI] Quét tên riêng \(turnLabel) không trả về name sau khi thử lại (có thể bị từ chối), bỏ qua")
                }
            } catch where !Task.isCancelled && Self.shouldStopBatch(on: error) {
                // Hết hạn mức / chặn IP / mất đăng nhập (Gemini Web), captcha / prompt quá dài (Chế độ AI, 1.3.609): gọi
                // tiếp chỉ làm bị chặn nặng hơn. Dừng và báo rõ; phần đã quét vẫn nằm trong `batchExtractedNames` của
                // coordinator, được giữ lại trong tin kết quả (1.3.602 — điểm tiếp nối đã ghi theo phần đó). Thông điệp
                // giữ mô tả lỗi gốc ⇒ có `GoogleAIModeError.captchaMarker` cho nút xác minh.
                let tag = providerSwitch.config.activeProfile.isGoogleAIMode ? "[AIMode]" : "[GeminiWeb]"
                AppLogger.shared.log("❌ 🤖 \(tag) Dừng quét tên riêng ở \(turnLabel): \(error.localizedDescription)")
                let verb = isRetry ? "Dừng thử lại" : "Dừng quét"
                throw NSError(domain: "AINameExtraction", code: 429, userInfo: [
                    NSLocalizedDescriptionKey: "\(verb) sau \(position)/\(turns.count) lượt — \(error.localizedDescription) Các tên đã quét được vẫn giữ trong tin kết quả."
                ])
            } catch {
                if Task.isCancelled || error is CancellationError { break }
                // Lỗi lẻ của một lượt (mạng, model trả sai định dạng…): bỏ qua lượt đó và quét tiếp, có log và có đếm.
                progress.failedBatches += 1
                failed.append(turn)
                AppLogger.shared.log("❌ 🤖 [AI] Quét tên riêng \(turnLabel) lỗi, bỏ qua: \(error.localizedDescription)")
            }

            // Chỉ lượt xong mà KHÔNG bị huỷ mới được tính vào điểm tiếp nối: lượt bị huỷ thì tên của nó không tới tay
            // coordinator.
            if Task.isCancelled { break }
            if let resume {
                resume.markCompleted(turnIndex: turn.turnIndex, succeeded: succeeded)
                progress.resumeChapterIndex = resume.resumeChapterIndex
            }
            onProgress(progress, Self.sortedNames(aggregatedNames))

            // Chế độ AI của Google nghỉ 5 s trong `GoogleAIModeTurnQueue` (khoảng nghỉ toàn cục, mọi truyện).
            if providerSwitch.config.activeProfile.isGeminiWeb, position < turns.count - 1 {
                try? await Task.sleep(nanoseconds: Self.geminiWebTurnPause)
            }
        }

        return (Self.sortedNames(aggregatedNames), progress, failed, resume)
    }

    /// Gửi một lượt; trả về rỗng (sau bộ lọc của `parseNamesFromText`) ⇒ nghỉ rồi gửi lại **đúng** lượt đó một lần
    /// (cùng prompt, cùng cuộc chat) — kể cả khi AI trả lời "Không có name" (người dùng chọn: vẫn thử lại). Lần hai có
    /// tên thì dùng; vẫn rỗng thì `saidNoNames` = một trong hai lần đã trả lời đúng "Không có name" (lượt hợp lệ), không
    /// thì vòng lượt tính là lỗi. Huỷ trong lúc nghỉ ⇒ `Task.sleep` ném `CancellationError`, vòng lượt dừng như mọi lần
    /// huỷ khác.
    func extractTurnRetryingEmpty(
        _ turn: AINameScanFailedBatch,
        turnLabel: String,
        config: AIConfiguration,
        promptOverride: String?,
        conversationId: UUID?
    ) async throws -> (names: [AIExtractedName], saidNoNames: Bool) {
        let first = try await extractNamesFromText(
            text: turn.text,
            config: config,
            promptOverride: promptOverride,
            conversationId: conversationId,
            turnLabel: turnLabel
        )
        guard first.names.isEmpty else { return first }
        try Task.checkCancellation()
        let reason = first.saidNoNames ? "trả lời \"Không có name\"" : "không trả về name"
        AppLogger.shared.log("🤖 [AI] Quét tên riêng: \(turnLabel) \(reason), nghỉ rồi gửi lại một lần")
        let isGeminiWeb = config.activeProfile.isGeminiWeb
        try await Task.sleep(nanoseconds: isGeminiWeb ? Self.geminiWebTurnPause : Self.emptyTurnRetryPause)
        let second = try await extractNamesFromText(
            text: turn.text,
            config: config,
            promptOverride: promptOverride,
            conversationId: conversationId,
            turnLabel: turnLabel
        )
        guard second.names.isEmpty else { return second }
        return ([], first.saidNoNames || second.saidNoNames)
    }

    /// Ghi chương đầu/cuối (hiển thị) của lượt sắp gửi vào tiến độ, kèm tên đã dịch theo `style` (`nil` = tên gốc đã
    /// trim). Lượt một chương chỉ dịch một lần.
    static func markSending(
        _ turn: AINameScanFailedBatch,
        style: AINameScanChapterTitleStyle?,
        into progress: inout AINameScanProgress
    ) {
        let display: (String) -> String = { raw in
            style?.displayTitle(raw) ?? raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let isSingle = turn.displayLastChapterIndex == turn.firstChapterIndex
        let firstTitle = display(turn.firstChapterTitle)
        progress.sendingFirstChapterIndex = turn.firstChapterIndex
        progress.sendingLastChapterIndex = turn.displayLastChapterIndex
        progress.sendingFirstChapterTitle = firstTitle
        progress.sendingLastChapterTitle = isSingle ? firstTitle : display(turn.lastChapterTitle)
    }

    /// Gộp tên theo `original` đã trim, cộng dồn `occurrenceCount` — một luật duy nhất cho mọi vòng lượt.
    static func aggregate(_ items: [AIExtractedName], into aggregatedNames: inout [String: AIExtractedName]) {
        for item in items {
            let orig = item.original.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !orig.isEmpty else { continue }
            if var existing = aggregatedNames[orig] {
                existing.occurrenceCount += item.occurrenceCount
                aggregatedNames[orig] = existing
            } else {
                aggregatedNames[orig] = item
            }
        }
    }

    static func sortedNames(_ aggregatedNames: [String: AIExtractedName]) -> [AIExtractedName] {
        Array(aggregatedNames.values).sorted(by: { $0.occurrenceCount > $1.occurrenceCount })
    }
}
