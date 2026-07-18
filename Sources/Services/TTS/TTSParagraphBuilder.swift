import Foundation

enum TTSParagraphBuilder {
    static func build(
        from normalizedText: NormalizedChapterText,
        chunkLength: Int
    ) -> [TTSParagraph] {
        let maximumLength = max(chunkLength, 10)
        return normalizedText.lines.flatMap { line in
            chunks(for: line, maximumLength: maximumLength)
        }
    }

    private static func chunks(
        for line: ChapterTextLine,
        maximumLength: Int
    ) -> [TTSParagraph] {
        guard line.text.utf16.count > maximumLength else {
            return [TTSParagraph(
                text: line.text,
                range: line.utf16Range,
                paragraphIndex: line.id
            )]
        }

        let characters = Array(line.text)
        var utf16Offsets = [Int](repeating: 0, count: characters.count + 1)
        for index in characters.indices {
            utf16Offsets[index + 1] = utf16Offsets[index] + characters[index].utf16.count
        }

        let sentenceMarks: Set<Character> = [".", "!", "?", "。", "！", "？"]
        let clauseMarks: Set<Character> = [",", "，", ";", "；", ":", "：", "、"]
        var result: [TTSParagraph] = []
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
                result.append(TTSParagraph(
                    text: text,
                    range: NSRange(
                        location: line.utf16Range.location + utf16Offsets[start] + leading,
                        length: text.utf16.count
                    ),
                    paragraphIndex: line.id
                ))
            }

            start = end
            while start < characters.count, characters[start].isWhitespace {
                start += 1
            }
        }

        return result
    }
}
