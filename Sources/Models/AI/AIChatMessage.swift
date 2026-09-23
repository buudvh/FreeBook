import Foundation

/// Một tin nhắn trong phiên trò chuyện AI.
public struct AIChatMessage: Identifiable, Codable, Sendable, Equatable {
    /// Vai trò của người gửi trong cuộc trò chuyện AI.
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
        case tool
    }

    public let id: UUID
    public let role: Role
    public var content: String
    public let timestamp: Date
    public var isStreaming: Bool
    public var harnessActions: [AIHarnessAction]?
    public var extractedNames: [AIExtractedName]?

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        harnessActions: [AIHarnessAction]? = nil,
        extractedNames: [AIExtractedName]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.harnessActions = harnessActions
        self.extractedNames = extractedNames
    }
}
