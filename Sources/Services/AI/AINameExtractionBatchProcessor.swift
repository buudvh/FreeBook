import Foundation

/// Điều phối việc quét và trích xuất tên riêng trên toàn bộ các chương đã tải theo từng batch.
///
/// Kích thước batch theo provider (1.3.515):
/// - Provider API: 5 chương/lượt, cắt 15.000 ký tự (như cũ).
/// - Gemini Web: gom chương liền nhau tới ~40.000 ký tự/lượt, **không cắt giữa chương** (chỉ cắt khi một chương đơn lẻ
///   dài hơn mức đó). Đã thử thật: prompt 15k/40k/80k ký tự chữ Hán đều trả `Tên=Nghĩa` trong 5–9 s. Ít lượt hơn ⇒ ít
///   prompt tính vào hạn mức ngày, ít lần nghỉ 2 s.
/// - Gemini Web + công tắc "Lưu chat vào lịch sử Gemini" bật (1.3.524): mỗi lượt là một lượt **nối tiếp cuộc chat
///   Gemini của phiên chat app** (`AIChatSession.id`, lưu trạng thái — cùng cuộc chat với chat thường, không xoay
///   sang chat mới), lượt nào cũng kèm prompt trích xuất. Tắt thì mỗi lượt là chat tạm độc lập, đủ prompt.
/// - Mọi lượt gửi đều có nhãn "lượt N/T" trong tin gửi và một dòng log `gửi lượt N/T` để đối chiếu với số tin thật.
/// - Lượt lỗi lẻ (1.3.527): hết vòng quét chính thì **tự thử lại một vòng** đúng các lượt lỗi (để cuối chứ không thử
///   ngay, cho Google kịp sinh xong lượt app đã cắt); lượt vẫn lỗi trả về cho coordinator giữ trong RAM để người dùng
///   bấm "Thử lại k lượt lỗi" (`retryFailedBatches`, một vòng mỗi lần bấm). Mọi vòng đi chung `runTurns`.
public final class AINameExtractionBatchProcessor: Sendable {
    public static let shared = AINameExtractionBatchProcessor()

    /// Kết quả một lần quét/thử lại: tên đã gộp, tiến độ tóm tắt, các lượt vẫn lỗi.
    public typealias ScanOutcome = (names: [AIExtractedName], progress: AINameScanProgress, failedBatches: [AINameScanFailedBatch])

    private static let apiChaptersPerBatch = 5
    private static let apiCharacterLimit = 15_000
    private static let geminiWebCharacterLimit = 40_000
    /// Gemini Web nhận ~40.000 ký tự rồi nghĩ lâu: log thật (1.3.524) thấy gói đầu về ngay rồi im > 45 s ⇒ mọi lượt
    /// timeout ở mức mặc định.
    private static let geminiWebIdleTimeout: TimeInterval = 150
    /// Trần tuyệt đối của một lượt quét Gemini Web (1.3.527). Log thật: lượt 3, 4, 6 lỗi `StreamGenerate lỗi sau
    /// ~244000 ms, chunk=5` — Gemini vẫn đang stream chậm thì chạm trần mặc định 240 s của `GeminiWebSessionController`
    /// (không phải idle timeout), app cắt ngang trong khi Google vẫn sinh tiếp.
    private static let geminiWebAbsoluteTimeout: TimeInterval = 600
    /// Nghỉ giữa các lượt Gemini Web để không bị coi là tự động hoá dồn dập (1037 hết hạn mức, 1060 chặn IP).
    private static let geminiWebTurnPause: UInt64 = 2_000_000_000

    private init() {}

    /// Quét tên riêng trên một đoạn văn bản (một chương hoặc một batch).
    /// `conversationId` khác nil (chỉ Gemini Web) ⇒ gửi như một lượt nối tiếp cuộc chat Gemini của phiên chat đó (lưu
    /// trạng thái), ép kèm prompt trích xuất (`forceContext`) — prompt không đổi giữa các lượt nên so băm sẽ bỏ nó từ
    /// lượt 2. `turnLabel` ("lượt N/T") gắn vào tin gửi.
    public func extractNamesFromText(
        text: String,
        config: AIConfiguration,
        promptOverride: String? = nil,
        characterLimit: Int? = nil,
        conversationId: UUID? = nil,
        turnLabel: String? = nil
    ) async throws -> [AIExtractedName] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let systemInstruction = resolveSystemInstruction(config: config, promptOverride: promptOverride)
        let limit = characterLimit ?? (config.activeProfile.isGeminiWeb ? Self.geminiWebCharacterLimit : Self.apiCharacterLimit)
        let truncated = String(text.prefix(limit))
        let header = turnLabel.map { "Văn bản raw chương truyện (\($0)):" } ?? "Văn bản raw chương truyện:"
        let messages = [
            OpenAIChatRequest.Message(role: "system", content: systemInstruction),
            OpenAIChatRequest.Message(role: "user", content: "\(header)\n\n\(truncated)")
        ]

        let content: String?
        if config.activeProfile.isGeminiWeb {
            if let conversationId {
                content = try await GeminiWebClient.shared.sendConversation(
                    config: config,
                    messages: messages,
                    sessionId: conversationId,
                    persist: true,
                    forceContext: true,
                    idleTimeout: Self.geminiWebIdleTimeout,
                    absoluteTimeout: Self.geminiWebAbsoluteTimeout
                )
            } else {
                let (res, _) = try await GeminiWebClient.shared.sendChat(
                    config: config,
                    messages: messages,
                    idleTimeout: Self.geminiWebIdleTimeout,
                    absoluteTimeout: Self.geminiWebAbsoluteTimeout
                )
                content = res
            }
        } else if config.activeProfile.apiFormat == "anthropic" {
            let (res, _) = try await AnthropicClient.shared.sendChat(config: config, messages: messages)
            content = res
        } else {
            let (res, _) = try await OpenAIClient.shared.sendChat(config: config, messages: messages)
            content = res
        }
        guard let content = content else { return [] }

        return parseNamesFromText(content)
    }

    /// Lỗi Gemini Web khiến gọi tiếp vô ích (và có hại cho tài khoản): dừng cả lượt quét thay vì nuốt như lỗi lẻ.
    private static func shouldStopBatch(on error: GeminiWebError) -> Bool {
        switch error {
        case .usageLimit, .ipBlocked, .notSignedIn, .accountStatus: return true
        default: return false
        }
    }

    /// Prompt hệ thống: ưu tiên prompt tự nhập cho lần quét này, rồi tới prompt đã lưu, cuối cùng là mặc định.
    private func resolveSystemInstruction(config: AIConfiguration, promptOverride: String?) -> String {
        if let override = promptOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return override
        }
        let saved = config.nameExtractionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return saved.isEmpty ? AIConfiguration.defaultNameExtractionPrompt : saved
    }

    /// Gom văn bản chương thành các batch. Gemini Web: theo số ký tự, không cắt giữa chương; API: 5 chương/batch.
    private static func makeBatches(_ texts: [String], isGeminiWeb: Bool) -> [String] {
        guard isGeminiWeb else {
            return stride(from: 0, to: texts.count, by: apiChaptersPerBatch).map { start in
                texts[start..<min(start + apiChaptersPerBatch, texts.count)].joined(separator: "\n\n")
            }
        }
        var batches: [String] = []
        var current = ""
        for text in texts {
            if !current.isEmpty, current.count + text.count + 2 > geminiWebCharacterLimit {
                batches.append(current)
                current = ""
            }
            current += current.isEmpty ? text : "\n\n" + text
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    /// Bật lưu lịch sử ⇒ đúng cuộc chat Gemini của phiên chat app (cùng khoá với chat thường), một chat cho cả lần
    /// quét. Tắt (hoặc không có phiên) ⇒ mỗi lượt là chat tạm độc lập.
    private static func chatConversationId(config: AIConfiguration, sessionId: UUID?) -> UUID? {
        (config.activeProfile.isGeminiWeb && GeminiWebConversationStore.saveToHistory) ? sessionId : nil
    }

    /// Quét tên riêng trên các chương đã tải về máy theo batch.
    /// `fromChapterIndex` khác nil thì chỉ quét từ chương đó trở đi (chế độ "từ chương đang đọc").
    /// `limit` khác nil thì chỉ quét `limit` chương đầu tiên của phạm vi đó.
    /// `sessionId` là id phiên chat app — Gemini Web + bật lưu lịch sử thì quét nối tiếp cuộc chat Gemini của phiên này.
    ///
    /// `onProgress` (1.3.524) báo: khi đã biết số chương (đang chuẩn bị), **trước** mỗi lượt (`sendingBatch` = lượt sắp
    /// gửi, tên = `nil` vì chưa đổi) và sau mỗi lượt (danh sách tên gộp + số lượt lỗi). Vòng tự thử lại ở cuối báo với
    /// `isRetry == true` (1.3.527).
    ///
    /// Trả về `progress` **tóm tắt**: `totalBatches` = số lượt của vòng chính, `failedBatches` = số lượt **vẫn** lỗi sau
    /// vòng tự thử lại, `isRetry` = đã chạy vòng tự thử lại; mảng `failedBatches` = chính các lượt vẫn lỗi.
    ///
    /// Bị huỷ (người dùng bấm dừng) ⇒ thoát ngay, **không** báo tiến độ nữa và không tự thử lại: lỗi huỷ của request
    /// đang bay từng bị coi là "lỗi lẻ của một nhóm", vòng quét bỏ qua rồi gọi `onProgress` ⇒ dải batch sống lại, phải
    /// bấm dừng lần hai (1.3.515).
    public func extractNamesFromDownloadedChapters(
        bookId: String,
        config: AIConfiguration,
        promptOverride: String? = nil,
        fromChapterIndex: Int? = nil,
        limit: Int? = nil,
        sessionId: UUID? = nil,
        onProgress: @escaping @Sendable (AINameScanProgress, [AIExtractedName]?) -> Void
    ) async throws -> ScanOutcome {
        var preparing = AINameScanProgress()
        let downloaded = await AIBookDataInspector.shared.fetchDownloadedChapters(
            bookId: bookId,
            fromChapterIndex: fromChapterIndex,
            limit: limit
        )
        guard !downloaded.isEmpty, !Task.isCancelled else { return ([], preparing, []) }
        preparing.chapterCount = downloaded.count
        onProgress(preparing, nil)

        var texts: [String] = []
        for chapter in downloaded {
            if Task.isCancelled { return ([], preparing, []) }
            if let raw = await AIBookDataInspector.shared.readRawChapterContent(bookId: bookId, snapshot: chapter),
               !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                texts.append(raw)
            }
        }
        let isGeminiWeb = config.activeProfile.isGeminiWeb
        let batches = Self.makeBatches(texts, isGeminiWeb: isGeminiWeb)
        let turns = batches.enumerated().map { item in
            AINameScanFailedBatch(text: item.element, turnIndex: item.offset + 1, totalTurns: batches.count)
        }
        let conversationId = Self.chatConversationId(config: config, sessionId: sessionId)
        await logRunStart(
            "\(texts.count) chương → \(batches.count) lượt",
            config: config,
            sessionId: sessionId,
            conversationId: conversationId
        )

        var outcome = try await runTurns(
            turns,
            seedNames: [],
            config: config,
            promptOverride: promptOverride,
            conversationId: conversationId,
            isRetry: false,
            chapterCount: downloaded.count,
            onProgress: onProgress
        )
        var summary = AINameScanProgress(
            sendingBatch: batches.count,
            totalBatches: batches.count,
            failedBatches: outcome.failedBatches.count,
            chapterCount: downloaded.count
        )

        // Tự thử lại một vòng ở CUỐI lần quét (không thử ngay sau lượt lỗi): lượt bị app cắt ở trần tuyệt đối có thể
        // vẫn đang được Google sinh nốt — để cuối thì Google kịp xong, lượt nối tiếp không bị từ chối.
        if !outcome.failedBatches.isEmpty, !Task.isCancelled {
            AppLogger.shared.log("🤖 [AI] Quét tên riêng: tự thử lại \(outcome.failedBatches.count) lượt lỗi ở cuối lần quét")
            if isGeminiWeb {
                try? await Task.sleep(nanoseconds: Self.geminiWebTurnPause)
            }
            if !Task.isCancelled {
                outcome = try await runTurns(
                    outcome.failedBatches,
                    seedNames: outcome.names,
                    config: config,
                    promptOverride: promptOverride,
                    conversationId: conversationId,
                    isRetry: true,
                    chapterCount: downloaded.count,
                    onProgress: onProgress
                )
                summary.failedBatches = outcome.failedBatches.count
                summary.isRetry = true
            }
        }
        return (outcome.names, summary, outcome.failedBatches)
    }

    /// Nút "Thử lại k lượt lỗi" (1.3.527): chạy **một** vòng đúng các lượt còn lỗi — không tự thử lại thêm. Tên mới
    /// gộp vào `existingNames` theo cùng luật với lần quét. Cùng prompt, cùng cuộc chat Gemini của phiên, cùng timeout.
    /// `progress` trả về: `totalBatches` = số lượt đã thử lại, `failedBatches` = số lượt vẫn lỗi, `isRetry == true`.
    public func retryFailedBatches(
        _ batches: [AINameScanFailedBatch],
        existingNames: [AIExtractedName],
        config: AIConfiguration,
        promptOverride: String? = nil,
        sessionId: UUID? = nil,
        onProgress: @escaping @Sendable (AINameScanProgress, [AIExtractedName]?) -> Void
    ) async throws -> ScanOutcome {
        let conversationId = Self.chatConversationId(config: config, sessionId: sessionId)
        await logRunStart(
            "thử lại \(batches.count) lượt lỗi (bấm nút)",
            config: config,
            sessionId: sessionId,
            conversationId: conversationId
        )
        return try await runTurns(
            batches,
            seedNames: existingNames,
            config: config,
            promptOverride: promptOverride,
            conversationId: conversationId,
            isRetry: true,
            chapterCount: nil,
            onProgress: onProgress
        )
    }

    /// Dòng log mở đầu một lần quét/thử lại — kèm công tắc lưu lịch sử, id phiên và cid cuộc chat Gemini hiện có, để
    /// đối chiếu khi Gemini tách nhiều cuộc chat (1.3.527). Không phải lỗi ⇒ không gắn ❌.
    private func logRunStart(_ summary: String, config: AIConfiguration, sessionId: UUID?, conversationId: UUID?) async {
        let isGeminiWeb = config.activeProfile.isGeminiWeb
        var detail = "GeminiWeb=\(isGeminiWeb), chat phiên=\(conversationId != nil)"
        if isGeminiWeb {
            var cidPrefix: String?
            if let sessionId {
                cidPrefix = await GeminiWebClient.shared.conversationCidPrefix(sessionId: sessionId)
            }
            let sessionPrefix = sessionId.map { String($0.uuidString.prefix(8)) } ?? "không có"
            detail += ", lưu lịch sử=\(GeminiWebConversationStore.saveToHistory), phiên=\(sessionPrefix), cid=\(cidPrefix ?? "không có")"
        }
        AppLogger.shared.log("🤖 [AI] Quét tên riêng: \(summary) (\(detail))")
    }

    /// Vòng gửi từng lượt — dùng chung cho vòng quét chính, vòng tự thử lại ở cuối và nút "Thử lại k lượt lỗi"
    /// (1.3.527): cùng prompt, cùng cuộc chat của phiên, cùng timeout, cùng nghỉ 2 s, cùng cách đếm lỗi và huỷ.
    /// `seedNames`: danh sách đã có — tên mới gộp vào đó nên danh sách báo qua `onProgress` luôn đầy đủ.
    private func runTurns(
        _ turns: [AINameScanFailedBatch],
        seedNames: [AIExtractedName],
        config: AIConfiguration,
        promptOverride: String?,
        conversationId: UUID?,
        isRetry: Bool,
        chapterCount: Int?,
        onProgress: @escaping @Sendable (AINameScanProgress, [AIExtractedName]?) -> Void
    ) async throws -> ScanOutcome {
        var progress = AINameScanProgress(totalBatches: turns.count, chapterCount: chapterCount, isRetry: isRetry)
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

            do {
                let batchResults = try await extractNamesFromText(
                    text: turn.text,
                    config: config,
                    promptOverride: promptOverride,
                    conversationId: conversationId,
                    turnLabel: turnLabel
                )
                Self.aggregate(batchResults, into: &aggregatedNames)
            } catch let error as GeminiWebError where !Task.isCancelled && Self.shouldStopBatch(on: error) {
                // Hết hạn mức / chặn IP / mất đăng nhập: gọi tiếp chỉ làm tài khoản bị chặn nặng hơn.
                // Dừng và báo rõ; phần đã quét vẫn nằm trong `batchExtractedNames` của coordinator.
                AppLogger.shared.log("❌ 🤖 [GeminiWeb] Dừng quét tên riêng ở \(turnLabel): \(error.localizedDescription)")
                let verb = isRetry ? "Dừng thử lại" : "Dừng quét"
                throw NSError(domain: "AINameExtraction", code: 429, userInfo: [
                    NSLocalizedDescriptionKey: "\(verb) sau \(position)/\(turns.count) lượt — \(error.localizedDescription) Các tên đã quét được vẫn hiện bên dưới."
                ])
            } catch {
                if Task.isCancelled || error is CancellationError { break }
                // Lỗi lẻ của một lượt (mạng, model trả sai định dạng…): bỏ qua lượt đó và quét tiếp, có log và có đếm.
                progress.failedBatches += 1
                failed.append(turn)
                AppLogger.shared.log("❌ 🤖 [AI] Quét tên riêng \(turnLabel) lỗi, bỏ qua: \(error.localizedDescription)")
            }

            if Task.isCancelled { break }
            onProgress(progress, Self.sortedNames(aggregatedNames))

            if isGeminiWeb, position < turns.count - 1 {
                try? await Task.sleep(nanoseconds: Self.geminiWebTurnPause)
            }
        }

        return (Self.sortedNames(aggregatedNames), progress, failed)
    }

    /// Gộp tên theo `original` đã trim, cộng dồn `occurrenceCount` — một luật duy nhất cho mọi vòng lượt.
    private static func aggregate(_ items: [AIExtractedName], into aggregatedNames: inout [String: AIExtractedName]) {
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

    private static func sortedNames(_ aggregatedNames: [String: AIExtractedName]) -> [AIExtractedName] {
        Array(aggregatedNames.values).sorted(by: { $0.occurrenceCount > $1.occurrenceCount })
    }

    /// Bóc tách danh sách tên riêng từ phản hồi AI dạng văn bản thuần, mỗi dòng đúng dạng `Tên gốc=Nghĩa`.
    /// Mọi dòng không chứa dấu `=` (lời giải thích, code fence, câu "Không có name"...) đều bị bỏ qua.
    public func parseNamesFromText(_ rawString: String) -> [AIExtractedName] {
        var results: [AIExtractedName] = []
        var indexByOriginal: [String: Int] = [:]

        for rawLine in rawString.components(separatedBy: .newlines) {
            guard let eqIndex = rawLine.firstIndex(of: "=") else { continue }

            let original = String(rawLine[..<eqIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let meaning = String(rawLine[rawLine.index(after: eqIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty, !meaning.isEmpty else { continue }

            if let existingIndex = indexByOriginal[original] {
                results[existingIndex].occurrenceCount += 1
            } else {
                indexByOriginal[original] = results.count
                results.append(AIExtractedName(
                    original: original,
                    suggestedMeaning: meaning,
                    category: "Tên riêng",
                    occurrenceCount: 1
                ))
            }
        }

        return results
    }
}
