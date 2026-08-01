import Foundation

struct ChapterTextLine: Identifiable, Sendable, Equatable {
    let id: Int
    let text: String
    let utf16Range: NSRange
}

struct NormalizedChapterText: Sendable, Equatable {
    let content: String
    let lines: [ChapterTextLine]
}

enum ChapterTextNormalizer {
    static func normalize(_ rawContent: String) -> NormalizedChapterText {
        let cleanRaw = JunkFilterManager.shared.filterRawContent(rawContent)
        let canonicalNewlines = cleanRaw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let allComponents = canonicalNewlines.components(separatedBy: "\n")
        var location = 0
        var lines: [ChapterTextLine] = []
        var nonEmptyTexts: [String] = []

        for (originalLineIndex, rawText) in allComponents.enumerated() {
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let length = text.utf16.count
            if !text.isEmpty {
                nonEmptyTexts.append(text)
                lines.append(ChapterTextLine(
                    id: originalLineIndex,
                    text: text,
                    utf16Range: NSRange(location: location, length: length)
                ))
            }
            location += length + 1
        }

        return NormalizedChapterText(
            content: nonEmptyTexts.joined(separator: "\n"),
            lines: lines
        )
    }
}

struct ChapterDocument: Sendable, Equatable {
    let chapterIndex: Int
    let title: String
    let url: String
    let host: String?
    let text: NormalizedChapterText
}
