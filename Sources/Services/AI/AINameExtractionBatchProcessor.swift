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
public final class AINameExtractionBatchProcessor: Sendable {
    public static let shared = AINameExtractionBatchProcessor()

    private static let apiChaptersPerBatch = 5
    private static let apiCharacterLimit = 15_000
    private static let geminiWebCharacterLimit = 40_000
    /// Gemini Web nhận ~40.000 ký tự rồi nghĩ lâu: log thật (1.3.524) thấy gói đầu về ngay rồi im > 45 s ⇒ mọi lượt
    /// timeout ở mức mặc định. Trần tuyệt đối của một fetch vẫn là 240 s (`GeminiWebSessionController`).
    private static let geminiWebIdleTimeout: TimeInterval = 150

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
                    idleTimeout: Self.geminiWebIdleTimeout
                )
            } else {
                let (res, _) = try await GeminiWebClient.shared.sendChat(
                    config: config,
                    messages: messages,
                    idleTimeout: Self.geminiWebIdleTimeout
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

    /// Quét tên riêng trên các chương đã tải về máy theo batch.
    /// `fromChapterIndex` khác nil thì chỉ quét từ chương đó trở đi (chế độ "từ chương đang đọc").
    /// `limit` khác nil thì chỉ quét `limit` chương đầu tiên của phạm vi đó.
    /// `sessionId` là id phiên chat app — Gemini Web + bật lưu lịch sử thì quét nối tiếp cuộc chat Gemini của phiên này.
    ///
    /// `onProgress` (1.3.524) báo: khi đã biết số chương (đang chuẩn bị), **trước** mỗi lượt (`sendingBatch` = lượt sắp
    /// gửi, tên = `nil` vì chưa đổi) và sau mỗi lượt (danh sách tên gộp + số lượt lỗi). Trả về kèm tiến độ cuối để
    /// coordinator biết số lượt lỗi.
    ///
    /// Bị huỷ (người dùng bấm dừng) ⇒ thoát ngay, **không** báo tiến độ nữa: lỗi huỷ của request đang bay từng bị
    /// coi là "lỗi lẻ của một nhóm", vòng quét bỏ qua rồi gọi `onProgress` ⇒ dải batch sống lại, phải bấm dừng lần
    /// hai (1.3.515).
    public func extractNamesFromDownloadedChapters(
        bookId: String,
        config: AIConfiguration,
        promptOverride: String? = nil,
        fromChapterIndex: Int? = nil,
        limit: Int? = nil,
        sessionId: UUID? = nil,
        onProgress: @escaping @Sendable (AINameScanProgress, [AIExtractedName]?) -> Void
    ) async throws -> (names: [AIExtractedName], progress: AINameScanProgress) {
        var progress = AINameScanProgress()
        let downloaded = await AIBookDataInspector.shared.fetchDownloadedChapters(
            bookId: bookId,
            fromChapterIndex: fromChapterIndex,
            limit: limit
        )
        guard !downloaded.isEmpty, !Task.isCancelled else { return ([], progress) }
        progress.chapterCount = downloaded.count
        onProgress(progress, nil)

        var texts: [String] = []
        for chapter in downloaded {
            if Task.isCancelled { return ([], progress) }
            if let raw = await AIBookDataInspector.shared.readRawChapterContent(bookId: bookId, snapshot: chapter),
               !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                texts.append(raw)
            }
        }
        let isGeminiWeb = config.activeProfile.isGeminiWeb
        let batches = Self.makeBatches(texts, isGeminiWeb: isGeminiWeb)
        // Bật lưu lịch sử ⇒ đúng cuộc chat Gemini của phiên chat app (cùng khoá với chat thường), một chat cho cả lần
        // quét. Tắt (hoặc không có phiên) ⇒ mỗi lượt là chat tạm độc lập.
        let conversationId = (isGeminiWeb && GeminiWebConversationStore.saveToHistory) ? sessionId : nil
        let characterLimit = isGeminiWeb ? Self.geminiWebCharacterLimit : Self.apiCharacterLimit
        progress.totalBatches = batches.count
        AppLogger.shared.log("🤖 [AI] Quét tên riêng: \(texts.count) chương → \(batches.count) lượt (GeminiWeb=\(isGeminiWeb), chat phiên=\(conversationId != nil))")

        var aggregatedNames: [String: AIExtractedName] = [:]

        for (index, combinedText) in batches.enumerated() {
            if Task.isCancelled { break }
            let turnLabel = "lượt \(index + 1)/\(batches.count)"
            progress.sendingBatch = index + 1
            onProgress(progress, nil)
            AppLogger.shared.log("🤖 [AI] Quét tên riêng: gửi \(turnLabel) (\(min(combinedText.count, characterLimit)) ký tự, chat phiên=\(conversationId != nil))")

            do {
                let batchResults = try await extractNamesFromText(
                    text: combinedText,
                    config: config,
                    promptOverride: promptOverride,
                    conversationId: conversationId,
                    turnLabel: turnLabel
                )
                for item in batchResults {
                    let orig = item.original.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !orig.isEmpty else { continue }
                    if var existing = aggregatedNames[orig] {
                        existing.occurrenceCount += item.occurrenceCount
                        aggregatedNames[orig] = existing
                    } else {
                        aggregatedNames[orig] = item
                    }
                }
            } catch let error as GeminiWebError where !Task.isCancelled && Self.shouldStopBatch(on: error) {
                // Hết hạn mức / chặn IP / mất đăng nhập: gọi tiếp chỉ làm tài khoản bị chặn nặng hơn.
                // Dừng và báo rõ; phần đã quét vẫn nằm trong `batchExtractedNames` của coordinator.
                AppLogger.shared.log("❌ 🤖 [GeminiWeb] Dừng quét tên riêng ở lượt \(index + 1)/\(batches.count): \(error.localizedDescription)")
                throw NSError(domain: "AINameExtraction", code: 429, userInfo: [
                    NSLocalizedDescriptionKey: "Dừng quét sau \(index)/\(batches.count) lượt — \(error.localizedDescription) Các tên đã quét được vẫn hiện bên dưới."
                ])
            } catch {
                if Task.isCancelled || error is CancellationError { break }
                // Lỗi lẻ của một lượt (mạng, model trả sai định dạng…): bỏ qua lượt đó và quét tiếp, có log và có đếm.
                progress.failedBatches += 1
                AppLogger.shared.log("❌ 🤖 [AI] Quét tên riêng lượt \(index + 1)/\(batches.count) lỗi, bỏ qua: \(error.localizedDescription)")
            }

            if Task.isCancelled { break }
            let currentList = Array(aggregatedNames.values).sorted(by: { $0.occurrenceCount > $1.occurrenceCount })
            onProgress(progress, currentList)

            // Gemini Web: nghỉ giữa các lượt để không bị coi là tự động hoá dồn dập (1037 hết hạn mức, 1060 chặn IP).
            if isGeminiWeb, index < batches.count - 1 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        let names = Array(aggregatedNames.values).sorted(by: { $0.occurrenceCount > $1.occurrenceCount })
        return (names, progress)
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
