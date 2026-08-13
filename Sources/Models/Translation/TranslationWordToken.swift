import Foundation

public struct TranslationWordToken: Identifiable, Hashable {
    public var id = UUID()
    public let originalText: String
    public let translatedText: String
    public let originalOffset: Int
    public let originalLength: Int

    public init(originalText: String, translatedText: String, originalOffset: Int, originalLength: Int) {
        self.originalText = originalText
        self.translatedText = translatedText
        self.originalOffset = originalOffset
        self.originalLength = originalLength
    }
}
