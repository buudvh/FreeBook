import Foundation

/// Điều phối việc quét và trích xuất tên riêng trên toàn bộ các chương đã tải theo từng batch.
public final class AINameExtractionBatchProcessor: Sendable {
    public static let shared = AINameExtractionBatchProcessor()

    private init() {}

    /// Quét tên riêng trên một chương duy nhất.
    public func extractNamesFromText(
        text: String,
        config: AIConfiguration
    ) async throws -> [AIExtractedName] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let systemInstruction = config.nameExtractionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AIConfiguration.defaultNameExtractionPrompt
            : config.nameExtractionPrompt

        // Giới hạn độ dài text nếu quá dài
        let truncated = String(text.prefix(15000))
        let messages = [
            OpenAIChatRequest.Message(role: "system", content: systemInstruction),
            OpenAIChatRequest.Message(role: "user", content: "Văn bản raw chương truyện:\n\n\(truncated)")
        ]

        let (content, _) = try await OpenAIClient.shared.sendChat(config: config, messages: messages)
        guard let content = content else { return [] }

        return parseNamesFromJSONString(content)
    }

    /// Quét tên riêng trên toàn bộ các chương đã tải về máy theo batch.
    public func extractNamesFromDownloadedChapters(
        bookId: String,
        config: AIConfiguration,
        onProgress: @escaping @Sendable (Int, Int, [AIExtractedName]) -> Void
    ) async throws -> [AIExtractedName] {
        let downloaded = await AIBookDataInspector.shared.fetchDownloadedChapters(bookId: bookId)
        guard !downloaded.isEmpty else { return [] }

        // Chia nhóm các chương thành các batch 5 chương
        let batchSize = 5
        var batches: [[StoredChapterSnapshot]] = []
        for i in stride(from: 0, to: downloaded.count, by: batchSize) {
            let end = min(i + batchSize, downloaded.count)
            batches.append(Array(downloaded[i..<end]))
        }

        var aggregatedNames: [String: AIExtractedName] = [:]
        let existingNames = Set(AIBookDataInspector.shared.fetchExistingNamesInBook(bookId: bookId))

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
                if let batchResults = try? await extractNamesFromText(text: combinedText, config: config) {
                    for item in batchResults {
                        let orig = item.original.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !orig.isEmpty, !existingNames.contains(orig) else { continue }
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

    private func parseNamesFromJSONString(_ rawString: String) -> [AIExtractedName] {
        var clean = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        // Bỏ bọc ```json ... ``` nếu model trả về markdown
        if clean.hasPrefix("```") {
            clean = clean.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = clean.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var results: [AIExtractedName] = []
        for dict in jsonArray {
            guard let orig = dict["original"] as? String, !orig.isEmpty,
                  let meaning = dict["meaning"] as? String, !meaning.isEmpty else {
                continue
            }
            let category = (dict["category"] as? String) ?? "Nhân vật"
            results.append(AIExtractedName(original: orig, suggestedMeaning: meaning, category: category))
        }
        return results
    }
}
