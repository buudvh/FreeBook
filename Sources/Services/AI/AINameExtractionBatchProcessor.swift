import Foundation

/// Điều phối việc quét và trích xuất tên riêng trên toàn bộ các chương đã tải theo từng batch.
public final class AINameExtractionBatchProcessor: Sendable {
    public static let shared = AINameExtractionBatchProcessor()

    private init() {}

    /// Quét tên riêng trên một chương duy nhất.
    public func extractNamesFromText(
        text: String,
        config: AIConfiguration,
        promptOverride: String? = nil
    ) async throws -> [AIExtractedName] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let systemInstruction = resolveSystemInstruction(config: config, promptOverride: promptOverride)

        // Giới hạn độ dài text nếu quá dài
        let truncated = String(text.prefix(15000))
        let messages = [
            OpenAIChatRequest.Message(role: "system", content: systemInstruction),
            OpenAIChatRequest.Message(role: "user", content: "Văn bản raw chương truyện:\n\n\(truncated)")
        ]

        let content: String?
        if config.activeProfile.isGeminiWeb {
            let (res, _) = try await GeminiWebClient.shared.sendChat(config: config, messages: messages)
            content = res
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

    /// Quét tên riêng trên các chương đã tải về máy theo batch.
    /// `fromChapterIndex` khác nil thì chỉ quét từ chương đó trở đi (chế độ "từ chương đang đọc").
    /// `limit` khác nil thì chỉ quét `limit` chương đầu tiên của phạm vi đó.
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

        // Chia nhóm các chương thành các batch 5 chương
        let batchSize = 5
        var batches: [[StoredChapterSnapshot]] = []
        for i in stride(from: 0, to: downloaded.count, by: batchSize) {
            let end = min(i + batchSize, downloaded.count)
            batches.append(Array(downloaded[i..<end]))
        }

        var aggregatedNames: [String: AIExtractedName] = [:]

        for (index, batch) in batches.enumerated() {
            if Task.isCancelled { break }

            var combinedText = ""
            for chapter in batch {
                if let raw = await AIBookDataInspector.shared.readRawChapterContent(bookId: bookId, snapshot: chapter) {
                    combinedText.append(raw)
                    combinedText.append("\n\n")
                }
            }

            if !combinedText.isEmpty {
                do {
                    let batchResults = try await extractNamesFromText(
                        text: combinedText,
                        config: config,
                        promptOverride: promptOverride
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
                } catch let error as GeminiWebError where Self.shouldStopBatch(on: error) {
                    // Hết hạn mức / chặn IP / mất đăng nhập: gọi tiếp chỉ làm tài khoản bị chặn nặng hơn.
                    // Dừng và báo rõ; phần đã quét vẫn nằm trong `batchExtractedNames` của coordinator.
                    AppLogger.shared.log("🤖 [GeminiWeb] Dừng quét tên riêng ở nhóm \(index + 1)/\(batches.count): \(error.localizedDescription)")
                    throw NSError(domain: "AINameExtraction", code: 429, userInfo: [
                        NSLocalizedDescriptionKey: "Dừng quét sau \(index)/\(batches.count) nhóm — \(error.localizedDescription) Các tên đã quét được vẫn hiện bên dưới."
                    ])
                } catch {
                    // Lỗi lẻ của một nhóm (mạng, model trả sai định dạng…): bỏ qua nhóm đó và quét tiếp — hành vi cũ, nay có log.
                    AppLogger.shared.log("🤖 [AI] Quét tên riêng nhóm \(index + 1)/\(batches.count) lỗi, bỏ qua: \(error.localizedDescription)")
                }
            }

            let currentList = Array(aggregatedNames.values).sorted(by: { $0.occurrenceCount > $1.occurrenceCount })
            onProgress(index + 1, batches.count, currentList)

            // Gemini Web: nghỉ giữa các nhóm để không bị coi là tự động hoá dồn dập (1037 hết hạn mức, 1060 chặn IP).
            if config.activeProfile.isGeminiWeb, index < batches.count - 1 {
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
