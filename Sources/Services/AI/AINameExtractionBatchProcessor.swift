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
        if config.activeProfile.apiFormat == "anthropic" {
            let (res, _) = try await AnthropicClient.shared.sendChat(config: config, messages: messages)
            content = res
        } else {
            let (res, _) = try await OpenAIClient.shared.sendChat(config: config, messages: messages)
            content = res
        }
        guard let content = content else { return [] }

        return parseNamesFromText(content)
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
    public func extractNamesFromDownloadedChapters(
        bookId: String,
        config: AIConfiguration,
        promptOverride: String? = nil,
        fromChapterIndex: Int? = nil,
        onProgress: @escaping @Sendable (Int, Int, [AIExtractedName]) -> Void
    ) async throws -> [AIExtractedName] {
        let downloaded = await AIBookDataInspector.shared.fetchDownloadedChapters(
            bookId: bookId,
            fromChapterIndex: fromChapterIndex
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
                if let batchResults = try? await extractNamesFromText(
                    text: combinedText,
                    config: config,
                    promptOverride: promptOverride
                ) {
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
                }
            }

            let currentList = Array(aggregatedNames.values).sorted(by: { $0.occurrenceCount > $1.occurrenceCount })
            onProgress(index + 1, batches.count, currentList)
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
