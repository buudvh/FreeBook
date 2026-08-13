import Foundation

public struct TTSParagraphSplitter: Sendable {
    public static let shared = TTSParagraphSplitter()

    public init() {}

    public func splitTextIntoParagraphs(_ text: String, maxLen: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.count <= maxLen { return [trimmed] }

        var result: [String] = []
        var current = ""

        let sentences = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        for s in sentences {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if current.count + t.count + 1 <= maxLen {
                current += (current.isEmpty ? "" : " ") + t
            } else {
                if !current.isEmpty { result.append(current) }
                current = t
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
