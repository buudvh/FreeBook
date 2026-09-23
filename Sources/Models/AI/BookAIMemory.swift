import Foundation

/// Trí nhớ dài hạn của AI theo từng cuốn truyện (nhân vật chính, môn phái, bối cảnh, ghi chú cốt truyện).
public struct BookAIMemory: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let bookId: String
    public var notes: String
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        bookId: String,
        notes: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.bookId = bookId
        self.notes = notes
        self.updatedAt = updatedAt
    }
}
