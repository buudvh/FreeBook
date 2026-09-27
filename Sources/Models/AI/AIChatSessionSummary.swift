import Foundation

/// Bản ghi tóm tắt thông tin nhẹ của một phiên chat AI, dùng cho mục lục và danh sách.
public struct AIChatSessionSummary: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let bookId: String
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date
    public var mode: AIHarnessMode
    public var model: String
    public var messageCount: Int
    public var providerProfileId: String?

    public init(
        id: UUID,
        bookId: String,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        mode: AIHarnessMode,
        model: String,
        messageCount: Int,
        providerProfileId: String? = nil
    ) {
        self.id = id
        self.bookId = bookId
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mode = mode
        self.model = model
        self.messageCount = messageCount
        self.providerProfileId = providerProfileId
    }

    public init(session: AIChatSession) {
        self.id = session.id
        self.bookId = session.bookId
        self.title = session.title
        self.createdAt = session.createdAt
        self.updatedAt = session.updatedAt
        self.mode = session.mode
        self.model = session.model
        self.messageCount = session.messages.count
        self.providerProfileId = session.providerProfileId
    }
}
