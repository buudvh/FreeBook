import Foundation

/// Điều phối việc quét và trích xuất tên riêng trên toàn bộ các chương đã tải theo từng batch.
///
/// Kích thước batch theo provider (1.3.515):
/// - Provider API: 5 chương/lượt, cắt 15.000 ký tự (như cũ).
/// - Gemini Web: gom chương liền nhau tới ~40.000 ký tự/lượt, **không cắt giữa chương** (chỉ cắt khi một chương đơn lẻ
///   dài hơn mức đó). Đã thử thật: prompt 15k/40k/80k ký tự chữ Hán đều trả `Tên=Nghĩa` trong 5–9 s. Ít lượt hơn ⇒ ít
///   prompt tính vào hạn mức ngày, ít lần nghỉ 2 s.
/// - Gemini Web + công tắc "Lưu chat vào lịch sử Gemini" bật: cả lần quét là **một** cuộc chat nối tiếp (mở cuộc chat
///   mới sau mỗi `geminiWebTurnsPerConversation` lượt để ngữ cảnh không phình); tắt thì mỗi lượt là chat tạm độc lập.
public final class AINameExtractionBatchProcessor: Sendable {
    public static let shared = AINameExtractionBatchProcessor()

    private static let apiChaptersPerBatch = 5
    private static let apiCharacterLimit = 15_000
    private static let geminiWebCharacterLimit = 40_000
    private static let geminiWebTurnsPerConversation = 5

    private init() {}

    /// Quét tên riêng trên một đoạn văn bản (một chương hoặc một batch).
    /// `conversationId` khác nil (chỉ Gemini Web) ⇒ gửi như một lượt của cuộc chat Gemini đó, không lưu trạng thái.
    public func extractNamesFromText(
        text: String,
        config: AIConfiguration,
        promptOverride: String? = nil,
        characterLimit: Int? = nil,
        conversationId: UUID? = nil
    ) async throws -> [AIExtractedName] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let systemInstruction = resolveSystemInstruction(config: config, promptOverride: promptOverride)
        let limit = characterLimit ?? (config.activeProfile.isGeminiWeb ? Self.geminiWebCharacterLimit : Self.apiCharacterLimit)
        let truncated = String(text.prefix(limit))
        let messages = [
            OpenAIChatRequest.Message(role: "system", content: systemInstruction),
            OpenAIChatRequest.Message(role: "user", content: "Văn bản raw chương truyện:\n\n\(truncated)")
        ]

        let content: String?
        if config.activeProfile.isGeminiWeb {
            if let conversationId {
                content = try await GeminiWebClient.shared.sendConversation(
                    config: config,
                    messages: messages,
                    sessionId: conversationId,
                    persist: false
                )
            } else {
                let (res, _) = try await GeminiWebClient.shared.sendChat(config: config, messages: messages)
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
        onProgress: @escaping @Sendable (Int, Int, [AIExtractedName]) -> Void
    ) async throws -> [AIExtractedName] {
        let downloaded = await AIBookDataInspector.shared.fetchDownloadedChapters(
            bookId: bookId,
            fromChapterIndex: fromChapterIndex,
            limit: limit
        )
        guard !downloaded.isEmpty else { return [] }

        var texts: [String] = []
        for chapter in downloaded {
            if Task.isCancelled { return [] }
            if let raw = await AIBookDataInspector.shared.readRawChapterContent(bookId: bookId, snapshot: chapter),
               !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                texts.append(raw)
            }
        }
        let isGeminiWeb = config.activeProfile.isGeminiWeb
        let batches = Self.makeBatches(texts, isGeminiWeb: isGeminiWeb)
        let useConversation = isGeminiWeb && GeminiWebConversationStore.saveToHistory
        var conversationId = UUID()
        AppLogger.shared.log("🤖 [AI] Quét tên riêng: \(texts.count) chương → \(batches.count) lượt (GeminiWeb=\(isGeminiWeb), nối tiếp=\(useConversation))")

        var aggregatedNames: [String: AIExtractedName] = [:]

        for (index, combinedText) in batches.enumerated() {
            if Task.isCancelled { break }
            if useConversation, index > 0, index % Self.geminiWebTurnsPerConversation == 0 {
                conversationId = UUID()
            }

            do {
                let batchResults = try await extractNamesFromText(
                    text: combinedText,
                    config: config,
                    promptOverride: promptOverride,
                    conversationId: useConversation ? conversationId : nil
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
                AppLogger.shared.log("🤖 [GeminiWeb] Dừng quét tên riêng ở lượt \(index + 1)/\(batches.count): \(error.localizedDescription)")
                throw NSError(domain: "AINameExtraction", code: 429, userInfo: [
                    NSLocalizedDescriptionKey: "Dừng quét sau \(index)/\(batches.count) lượt — \(error.localizedDescription) Các tên đã quét được vẫn hiện bên dưới."
                ])
            } catch {
                if Task.isCancelled || error is CancellationError { break }
                // Lỗi lẻ của một lượt (mạng, model trả sai định dạng…): bỏ qua lượt đó và quét tiếp, có log.
                AppLogger.shared.log("🤖 [AI] Quét tên riêng lượt \(index + 1)/\(batches.count) lỗi, bỏ qua: \(error.localizedDescription)")
            }

            if Task.isCancelled { break }
            let currentList = Array(aggregatedNames.values).sorted(by: { $0.occurrenceCount > $1.occurrenceCount })
            onProgress(index + 1, batches.count, currentList)

            // Gemini Web: nghỉ giữa các lượt để không bị coi là tự động hoá dồn dập (1037 hết hạn mức, 1060 chặn IP).
            if isGeminiWeb, index < batches.count - 1 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        return Array(aggregatedNames.values).sorted(by: { $0.occurrenceCount > $1.occurrenceCount })
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
