import Foundation

/// Một phiên trò chuyện với AI của một cuốn truyện.
public struct AIChatSession: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let bookId: String
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date
    public var messages: [AIChatMessage]
    public var mode: AIHarnessMode
    public var model: String

    public init(
        id: UUID = UUID(),
        bookId: String,
        title: String = "Phiên chat mới",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [AIChatMessage] = [],
        mode: AIHarnessMode = .bypass,
        model: String = "gemini-2.0-flash"
    ) {
        self.id = id
        self.bookId = bookId
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.mode = mode
        self.model = model
    }
}
