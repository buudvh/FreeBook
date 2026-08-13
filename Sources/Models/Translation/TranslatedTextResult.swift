import Foundation

public struct TranslatedTextResult: Codable, Equatable, Sendable {
    public let text: String
    public let spans: [TranslationSpan]

    public init(text: String, spans: [TranslationSpan]) {
        self.text = text
        self.spans = spans
    }
}
