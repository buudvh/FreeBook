import Foundation

public struct TTSHighlightCalculator: Sendable {
    public static let shared = TTSHighlightCalculator()

    public init() {}

    public func calculateHighlightRange(paragraphText: String, progress: Double) -> NSRange {
        guard !paragraphText.isEmpty, progress >= 0.0 else { return NSRange(location: 0, length: 0) }
        let totalChars = paragraphText.count
        let charIndex = min(totalChars, Int(Double(totalChars) * progress))
        return NSRange(location: 0, length: charIndex)
    }
}
