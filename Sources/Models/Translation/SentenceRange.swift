import Foundation

public struct SentenceRange {
    public let text: String
    public let range: NSRange

    public init(text: String, range: NSRange) {
        self.text = text
        self.range = range
    }
}
