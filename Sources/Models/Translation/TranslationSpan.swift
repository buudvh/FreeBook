import Foundation

public struct TranslationSpan: Codable, Equatable, Hashable, Sendable {
    public let originalLocation: Int
    public let originalLength: Int
    public let translatedLocation: Int
    public let translatedLength: Int

    public init(
        originalLocation: Int,
        originalLength: Int,
        translatedLocation: Int,
        translatedLength: Int
    ) {
        self.originalLocation = originalLocation
        self.originalLength = originalLength
        self.translatedLocation = translatedLocation
        self.translatedLength = translatedLength
    }

    public var originalRange: NSRange {
        NSRange(location: originalLocation, length: originalLength)
    }

    public var translatedRange: NSRange {
        NSRange(location: translatedLocation, length: translatedLength)
    }
}
