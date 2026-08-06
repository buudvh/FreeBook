import Foundation

public struct TTSLineEntry: Sendable {
    public let lineId: Int
    public let originalText: String
    public let translatedText: String
    public let spans: [TranslationSpan]

    public init(lineId: Int, originalText: String, translatedText: String, spans: [TranslationSpan] = []) {
        self.lineId = lineId
        self.originalText = originalText
        self.translatedText = translatedText
        self.spans = spans
    }
}

enum TTSParagraphBuilder {
    static func build(
        from normalizedText: NormalizedChapterText,
        chunkLength: Int
    ) -> [TTSParagraph] {
        let entries = normalizedText.lines.map {
            TTSLineEntry(lineId: $0.id, originalText: $0.text, translatedText: $0.text, spans: [])
        }
        return buildFromEntries(entries, chunkLength: chunkLength)
    }

    static func buildFromEntries(
        _ entries: [TTSLineEntry],
        chunkLength: Int
    ) -> [TTSParagraph] {
        let maximumLength = max(chunkLength, 10)
        return entries.flatMap { entry in
            chunks(for: entry, maximumLength: maximumLength)
        }
    }

    private static func chunks(
        for entry: TTSLineEntry,
        maximumLength: Int
    ) -> [TTSParagraph] {
        let textToUse = entry.translatedText
        guard textToUse.utf16.count > maximumLength else {
            let relativeRange = NSRange(location: 0, length: textToUse.utf16.count)
            let srcRange = mapSourceRange(
                translatedRange: relativeRange,
                originalText: entry.originalText,
                translatedText: textToUse,
                spans: entry.spans
            )
            AppLogger.shared.logTTSVerbose("🔊 [TTSParagraphBuilder] Short Chunk (Line \(entry.lineId), len=\(textToUse.count)): '\(textToUse.prefix(20))...' | relativeRange=\(relativeRange)")
            return [TTSParagraph(
                text: textToUse,
                range: relativeRange,
                paragraphIndex: entry.lineId,
                sourceRange: srcRange,
                boundaryKind: .paragraphEnd
            )]
        }

        let characters = Array(textToUse)
        var utf16Offsets = [Int](repeating: 0, count: characters.count + 1)
        for index in characters.indices {
            utf16Offsets[index + 1] = utf16Offsets[index] + characters[index].utf16.count
        }

        let sentenceMarks: Set<Character> = [".", "!", "?", "。", "！", "？"]
        let clauseMarks: Set<Character> = [",", "，", ";", "；", ":", "：", "、"]
        var rawChunks: [(text: String, range: NSRange, srcRange: NSRange)] = []
        var start = 0

        while start < characters.count {
            var end = start
            while end < characters.count,
                  utf16Offsets[end + 1] - utf16Offsets[start] <= maximumLength {
                end += 1
            }
            if end == start { end += 1 }

            if end < characters.count {
                let candidates = start..<end
                if let position = candidates.reversed().first(where: { sentenceMarks.contains(characters[$0]) }) {
                    end = position + 1
                } else if let position = candidates.reversed().first(where: { clauseMarks.contains(characters[$0]) }) {
                    end = position + 1
                } else if let position = candidates.reversed().first(where: { characters[$0].isWhitespace }) {
                    end = position + 1
                }
            }

            let raw = String(characters[start..<end])
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let leading = raw.prefix(while: { $0.isWhitespace }).utf16.count
                let relativeRange = NSRange(
                    location: utf16Offsets[start] + leading,
                    length: text.utf16.count
                )
                let srcRange = mapSourceRange(
                    translatedRange: relativeRange,
                    originalText: entry.originalText,
                    translatedText: textToUse,
                    spans: entry.spans
                )
                AppLogger.shared.logTTSVerbose("🔊 [TTSParagraphBuilder] Chunk (Line \(entry.lineId), len=\(text.count)): '\(text.prefix(20))...' | relativeRange=\(relativeRange)")
                rawChunks.append((text: text, range: relativeRange, srcRange: srcRange))
            }

            start = end
            while start < characters.count, characters[start].isWhitespace {
                start += 1
            }
        }

        return rawChunks.enumerated().map { idx, item in
            let isLast = (idx == rawChunks.count - 1)
            let kind: TTSBoundaryKind = isLast ? .paragraphEnd : .technicalChunk
            return TTSParagraph(
                text: item.text,
                range: item.range,
                paragraphIndex: entry.lineId,
                sourceRange: item.srcRange,
                boundaryKind: kind
            )
        }
    }

    private static func mapSourceRange(
        translatedRange: NSRange,
        originalText: String,
        translatedText: String,
        spans: [TranslationSpan]
    ) -> NSRange {
        guard !originalText.isEmpty else { return NSRange(location: 0, length: 0) }
        guard originalText != translatedText else { return translatedRange }

        let overlappingSpans = spans.filter {
            NSIntersectionRange($0.translatedRange, translatedRange).length > 0
        }
        if !overlappingSpans.isEmpty {
            let start = overlappingSpans.map(\.originalLocation).min() ?? 0
            let end = overlappingSpans.map { $0.originalLocation + $0.originalLength }.max() ?? start
            let range = NSRange(location: start, length: max(0, end - start))
            if range.location >= 0 && NSMaxRange(range) <= (originalText as NSString).length {
                return range
            }
        }

        let transLength = max(1, (translatedText as NSString).length)
        let origLength = max(1, (originalText as NSString).length)
        let ratio = Double(translatedRange.location) / Double(transLength)
        let loc = min(Int((ratio * Double(origLength)).rounded()), max(0, origLength - 1))
        let lenRatio = Double(translatedRange.length) / Double(transLength)
        let len = max(1, min(Int((lenRatio * Double(origLength)).rounded()), max(1, origLength - loc)))
        return NSRange(location: loc, length: len)
    }
}
