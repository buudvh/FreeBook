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

        let content: String?
        if config.activeProfile.apiFormat == "anthropic" {
            let (res, _) = try await AnthropicClient.shared.sendChat(config: config, messages: messages)
            content = res
        } else {
            let (res, _) = try await OpenAIClient.shared.sendChat(config: config, messages: messages)
            content = res
        }
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

    private func parseNamesFromJSONString(_ rawString: String) -> [AIExtractedName] {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 1. Thử trích xuất từ khối markdown code block ```json ... ``` hoặc ``` ... ```
        if let block = extractMarkdownBlock(from: trimmed), let items = tryParseJSON(block) {
            return items
        }

        // 2. Thử parse trực tiếp chuỗi trimmed
        if let items = tryParseJSON(trimmed) {
            return items
        }

        // 3. Nếu chưa parse được, tìm dải JSON substring bắt đầu bằng '[' đến ']' cuối cùng (mảng JSON)
        if let firstBracket = trimmed.firstIndex(of: "["),
           let lastBracket = trimmed.lastIndex(of: "]"),
           firstBracket < lastBracket {
            let slice = String(trimmed[firstBracket...lastBracket])
            if let items = tryParseJSON(slice) {
                return items
            }
        }

        // 4. Tìm dải JSON object '{' đến '}' cuối cùng (đề phòng AI bọc {"names": [...]})
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}"),
           firstBrace < lastBrace {
            let slice = String(trimmed[firstBrace...lastBrace])
            if let items = tryParseJSON(slice) {
                return items
            }
        }

        return []
    }

    private func extractMarkdownBlock(from text: String) -> String? {
        guard let startRange = text.range(of: "```") else { return nil }
        let afterStart = text[startRange.upperBound...]
        var contentStart = afterStart.startIndex
        if afterStart.hasPrefix("json") {
            if let idx = afterStart.index(afterStart.startIndex, offsetBy: 4, limitedBy: afterStart.endIndex) {
                contentStart = idx
            }
        }
        let remaining = text[contentStart...]
        guard let endRange = remaining.range(of: "```") else { return nil }
        let extracted = String(remaining[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return extracted.isEmpty ? nil : extracted
    }

    private func cleanTrailingCommas(_ json: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: ",\\s*([}\\]])", options: []) else {
            return json
        }
        let range = NSRange(location: 0, length: json.utf16.count)
        return regex.stringByReplacingMatches(in: json, options: [], range: range, withTemplate: "$1")
    }

    private func tryParseJSON(_ jsonString: String) -> [AIExtractedName]? {
        let cleaned = cleanTrailingCommas(jsonString.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let data = cleaned.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        var rawList: [[String: Any]] = []

        if let array = jsonObject as? [[String: Any]] {
            rawList = array
        } else if let dict = jsonObject as? [String: Any] {
            let potentialKeys = ["names", "entities", "data", "result", "list", "items", "extracted_names", "characters"]
            for key in potentialKeys {
                if let subArray = dict[key] as? [[String: Any]] {
                    rawList = subArray
                    break
                }
            }
            if rawList.isEmpty {
                for (_, value) in dict {
                    if let subArray = value as? [[String: Any]] {
                        rawList = subArray
                        break
                    }
                }
            }
        }

        guard !rawList.isEmpty else { return nil }

        var results: [AIExtractedName] = []
        var seenOriginals: [String: Int] = [:]

        for dict in rawList {
            let originalCandidates: [Any?] = [
                dict["original"], dict["name"], dict["word"], dict["hanzi"],
                dict["raw"], dict["chinese"], dict["text"]
            ]
            var origStr = ""
            for candidate in originalCandidates {
                if let str = candidate as? String, !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    origStr = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
            guard !origStr.isEmpty else { continue }

            let meaningCandidates: [Any?] = [
                dict["suggestedMeaning"], dict["meaning"], dict["translation"],
                dict["vietnamese"], dict["hvdic"], dict["hanviet"],
                dict["viet"], dict["val"], dict["value"]
            ]
            var meaningStr = ""
            for candidate in meaningCandidates {
                if let str = candidate as? String, !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    meaningStr = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
            guard !meaningStr.isEmpty else { continue }

            let categoryCandidates: [Any?] = [
                dict["category"], dict["type"], dict["tag"], dict["role"], dict["label"]
            ]
            var catStr = "Nhân vật"
            for candidate in categoryCandidates {
                if let str = candidate as? String, !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    catStr = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }

            let countCandidates: [Any?] = [
                dict["occurrenceCount"], dict["count"], dict["occurrences"], dict["frequency"]
            ]
            var countVal = 1
            for candidate in countCandidates {
                if let intVal = candidate as? Int, intVal > 0 {
                    countVal = intVal
                    break
                } else if let strVal = candidate as? String, let parsed = Int(strVal), parsed > 0 {
                    countVal = parsed
                    break
                }
            }

            if let existingIndex = seenOriginals[origStr] {
                results[existingIndex].occurrenceCount += countVal
            } else {
                seenOriginals[origStr] = results.count
                results.append(AIExtractedName(
                    original: origStr,
                    suggestedMeaning: meaningStr,
                    category: catStr,
                    occurrenceCount: countVal
                ))
            }
        }

        return results.isEmpty ? nil : results
    }
}
