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
    /// chặn điểm tiếp nối. Mỗi lượt xong mà không bị huỷ được ghi vào `resume`; báo sau lượt kèm điểm tiếp nối mới.
    func runTurns(
        _ turns: [AINameScanFailedBatch],
        seedNames: [AIExtractedName],
        config: AIConfiguration,
        promptOverride: String?,
        conversationId: UUID?,
        isRetry: Bool,
        chapterCount: Int?,
        resume: AINameScanResumeTracker?,
        onProgress: @escaping @Sendable (AINameScanProgress, [AIExtractedName]?) -> Void
    ) async throws -> ScanOutcome {
        var progress = AINameScanProgress(
            totalBatches: turns.count,
            chapterCount: chapterCount,
            isRetry: isRetry,
            preparedChapters: chapterCount ?? 0,
            resumeChapterIndex: resume?.resumeChapterIndex
        )
        var aggregatedNames: [String: AIExtractedName] = [:]
        Self.aggregate(seedNames, into: &aggregatedNames)
        var failed: [AINameScanFailedBatch] = []
        let isGeminiWeb = config.activeProfile.isGeminiWeb
        let characterLimit = isGeminiWeb ? Self.geminiWebCharacterLimit : Self.apiCharacterLimit

        for (position, turn) in turns.enumerated() {
            if Task.isCancelled { break }
            let turnLabel = isRetry ? "\(turn.turnLabel), thử lại" : turn.turnLabel
            progress.sendingBatch = position + 1
            onProgress(progress, nil)
            AppLogger.shared.log("🤖 [AI] Quét tên riêng: gửi \(turnLabel) (\(min(turn.text.count, characterLimit)) ký tự, chat phiên=\(conversationId != nil))")

            var succeeded = false
            do {
                let batchResults = try await extractTurnRetryingEmpty(
                    turn,
                    turnLabel: turnLabel,
                    config: config,
                    promptOverride: promptOverride,
                    conversationId: conversationId
                )
                if batchResults.isEmpty {
                    progress.failedBatches += 1
                    failed.append(turn)
                    AppLogger.shared.log("❌ 🤖 [AI] Quét tên riêng \(turnLabel) không trả về name sau khi thử lại (có thể bị từ chối), bỏ qua")
                } else {
                    Self.aggregate(batchResults, into: &aggregatedNames)
                    succeeded = true
                }
            } catch let error as GeminiWebError where !Task.isCancelled && Self.shouldStopBatch(on: error) {
                // Hết hạn mức / chặn IP / mất đăng nhập: gọi tiếp chỉ làm tài khoản bị chặn nặng hơn.
                // Dừng và báo rõ; phần đã quét vẫn nằm trong `batchExtractedNames` của coordinator, được giữ lại trong
                // tin kết quả (1.3.602 — điểm tiếp nối đã ghi theo phần đó).
                AppLogger.shared.log("❌ 🤖 [GeminiWeb] Dừng quét tên riêng ở \(turnLabel): \(error.localizedDescription)")
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

            if isGeminiWeb, position < turns.count - 1 {
                try? await Task.sleep(nanoseconds: Self.geminiWebTurnPause)
            }
        }

        return (Self.sortedNames(aggregatedNames), progress, failed, resume)
    }

    /// Gửi một lượt; trả về rỗng (sau bộ lọc của `parseNamesFromText`) ⇒ nghỉ rồi gửi lại **đúng** lượt đó một lần
    /// (cùng prompt, cùng cuộc chat). Kết quả lần hai trả nguyên cho vòng lượt — rỗng nữa thì vòng lượt tính là lỗi.
    /// Huỷ trong lúc nghỉ ⇒ `Task.sleep` ném `CancellationError`, vòng lượt dừng như mọi lần huỷ khác.
    private func extractTurnRetryingEmpty(
        _ turn: AINameScanFailedBatch,
        turnLabel: String,
        config: AIConfiguration,
        promptOverride: String?,
        conversationId: UUID?
    ) async throws -> [AIExtractedName] {
        let first = try await extractNamesFromText(
            text: turn.text,
            config: config,
            promptOverride: promptOverride,
            conversationId: conversationId,
            turnLabel: turnLabel
        )
        guard first.isEmpty else { return first }
        try Task.checkCancellation()
        AppLogger.shared.log("🤖 [AI] Quét tên riêng: \(turnLabel) không trả về name, nghỉ rồi gửi lại một lần")
        let isGeminiWeb = config.activeProfile.isGeminiWeb
        try await Task.sleep(nanoseconds: isGeminiWeb ? Self.geminiWebTurnPause : Self.emptyTurnRetryPause)
        return try await extractNamesFromText(
            text: turn.text,
            config: config,
            promptOverride: promptOverride,
            conversationId: conversationId,
            turnLabel: turnLabel
        )
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
