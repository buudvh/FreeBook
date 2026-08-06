import Foundation

enum NghiUtteranceSegmenter {
    private static let sentenceMarks: Set<Character> = [".", "!", "?", "。", "！", "？"]
    private static let phraseMarks: Set<Character> = [",", ";", ":", "，", "；", "：", "、"]
    private static let bracketMarks: Set<Character> = ["\"", "'", ")", "]", "}", "」", "』", "】", "］"]

    static func expand(_ paragraphs: [TTSParagraph], maximumLength: Int) -> [TTSParagraph] {
        let limit = max(1, maximumLength)
        return paragraphs.flatMap { split($0, maximumLength: limit) }
    }

    private static func split(_ paragraph: TTSParagraph, maximumLength: Int) -> [TTSParagraph] {
        let characters = Array(paragraph.text)
        guard !characters.isEmpty else { return [] }

        var utf16Offsets = [Int](repeating: 0, count: characters.count + 1)
        for index in characters.indices {
            utf16Offsets[index + 1] = utf16Offsets[index] + characters[index].utf16.count
        }

        var results: [TTSParagraph] = []
        var start = 0

        while start < characters.count {
            var maximumEnd = start
            while maximumEnd < characters.count,
                  utf16Offsets[maximumEnd + 1] - utf16Offsets[start] <= maximumLength {
                maximumEnd += 1
            }
            if maximumEnd == start { maximumEnd += 1 }

            let end: Int
            if let sentenceEnd = firstSentenceBoundary(in: characters, range: start..<maximumEnd) {
                end = includingClosingMarks(after: sentenceEnd, maximumEnd: maximumEnd, characters: characters)
            } else if maximumEnd == characters.count {
                end = maximumEnd
            } else if let phraseEnd = (start..<maximumEnd).reversed().first(where: { phraseMarks.contains(characters[$0]) }) {
                end = includingClosingMarks(after: phraseEnd, maximumEnd: maximumEnd, characters: characters)
            } else if let whitespaceEnd = (start..<maximumEnd).reversed().first(where: { characters[$0].isWhitespace }) {
                end = whitespaceEnd + 1
            } else {
                end = maximumEnd
            }

            let raw = String(characters[start..<end])
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let leading = raw.prefix(while: { $0.isWhitespace }).utf16.count
                let localRange = NSRange(
                    location: utf16Offsets[start] + leading,
                    length: text.utf16.count
                )
                let isLast = nextNonWhitespaceIndex(after: end, in: characters) >= characters.count
                results.append(TTSParagraph(
                    text: text,
                    range: offset(localRange, by: paragraph.range.location),
                    paragraphIndex: paragraph.paragraphIndex,
                    sourceRange: mappedSourceRange(localRange, paragraph: paragraph),
                    boundaryKind: boundaryKind(for: raw, isLast: isLast, parent: paragraph.boundaryKind)
                ))
            }

            start = nextNonWhitespaceIndex(after: end, in: characters)
        }

        return results
    }

    private static func firstSentenceBoundary(in characters: [Character], range: Range<Int>) -> Int? {
        range.first { index in
            let character = characters[index]
            guard sentenceMarks.contains(character) else { return character == "\n" || character == "\r" }
            if character == ".",
               index > 0,
               index + 1 < characters.count,
               characters[index - 1].isNumber,
               characters[index + 1].isNumber {
                return false
            }
            return true
        }
    }

    private static func includingClosingMarks(
        after boundaryIndex: Int,
        maximumEnd: Int,
        characters: [Character]
    ) -> Int {
        var end = boundaryIndex + 1
        while end < maximumEnd &&
              (sentenceMarks.contains(characters[end]) || bracketMarks.contains(characters[end])) {
            end += 1
        }
        return end
    }

    private static func boundaryKind(for rawText: String, isLast: Bool, parent: TTSBoundaryKind) -> TTSBoundaryKind {
        if isLast, parent != .technicalChunk {
            return parent
        }
        if rawText.contains("\n") || rawText.contains("\r") {
            return .newlineEnd
        }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else {
            return isLast ? parent : .technicalChunk
        }
        let trailingMarks = trimmed.reversed().prefix { character in
            sentenceMarks.contains(character) || phraseMarks.contains(character) || bracketMarks.contains(character)
        }
        if trailingMarks.contains(where: { sentenceMarks.contains($0) }) { return .sentenceEnd }
        if bracketMarks.contains(last) { return .bracketEnd }
        if phraseMarks.contains(last) { return .phraseEnd }
        return isLast ? parent : .technicalChunk
    }

    private static func nextNonWhitespaceIndex(after index: Int, in characters: [Character]) -> Int {
        var next = index
        while next < characters.count, characters[next].isWhitespace {
            next += 1
        }
        return next
    }

    private static func offset(_ range: NSRange, by amount: Int) -> NSRange {
        NSRange(location: range.location + amount, length: range.length)
    }

    private static func mappedSourceRange(_ localRange: NSRange, paragraph: TTSParagraph) -> NSRange {
        let textLength = max(1, paragraph.text.utf16.count)
        if paragraph.sourceRange.length == paragraph.range.length {
            return offset(localRange, by: paragraph.sourceRange.location)
        }

        let locationRatio = Double(localRange.location) / Double(textLength)
        let lengthRatio = Double(localRange.length) / Double(textLength)
        let sourceLocation = paragraph.sourceRange.location + Int((locationRatio * Double(paragraph.sourceRange.length)).rounded())
        let maximumLength = max(0, NSMaxRange(paragraph.sourceRange) - sourceLocation)
        let sourceLength = min(maximumLength, max(1, Int((lengthRatio * Double(paragraph.sourceRange.length)).rounded())))
        return NSRange(location: sourceLocation, length: sourceLength)
    }
}
