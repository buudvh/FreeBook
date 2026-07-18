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
        let canonicalNewlines = rawContent
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let texts = canonicalNewlines
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var location = 0
        let lines = texts.enumerated().map { id, text -> ChapterTextLine in
            let length = text.utf16.count
            defer { location += length + 1 }
            return ChapterTextLine(
                id: id,
                text: text,
                utf16Range: NSRange(location: location, length: length)
            )
        }

        return NormalizedChapterText(
            content: texts.joined(separator: "\n"),
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
