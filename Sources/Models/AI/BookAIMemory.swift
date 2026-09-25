import Foundation

/// Trí nhớ dài hạn của AI theo từng cuốn truyện (nhân vật chính, môn phái, bối cảnh, ghi chú cốt truyện).
public struct BookAIMemory: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let bookId: String
    /// Thông tin bối cảnh thế giới, nhân vật chính, môn phái, phe phái
    public var characterContext: String
    /// Tóm tắt diễn biến cốt truyện chính tích luỹ
    public var plotSummary: String
    /// Tóm lược từ điển Name riêng và VietPhrase riêng đã ghi nhận
    public var customDictionarySnapshot: String
    /// Ghi chú tuỳ chỉnh của người đọc
    public var notes: String
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        bookId: String,
        characterContext: String = "",
        plotSummary: String = "",
        customDictionarySnapshot: String = "",
        notes: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.bookId = bookId
        self.characterContext = characterContext
        self.plotSummary = plotSummary
        self.customDictionarySnapshot = customDictionarySnapshot
        self.notes = notes
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, bookId, characterContext, plotSummary, customDictionarySnapshot, notes, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.bookId = try container.decodeIfPresent(String.self, forKey: .bookId) ?? ""
        self.characterContext = try container.decodeIfPresent(String.self, forKey: .characterContext) ?? ""
        self.plotSummary = try container.decodeIfPresent(String.self, forKey: .plotSummary) ?? ""
        self.customDictionarySnapshot = try container.decodeIfPresent(String.self, forKey: .customDictionarySnapshot) ?? ""
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    /// Tổng hợp ngữ cảnh trí nhớ truyện thành văn bản nạp vào system prompt cho AI.
    public func compiledContextText() -> String {
        var sections: [String] = []

        let cleanChar = characterContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanChar.isEmpty {
            sections.append("### Bối cảnh & Nhân vật:\n\(cleanChar)")
        }

        let cleanPlot = plotSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanPlot.isEmpty {
            sections.append("### Diễn biến cốt truyện:\n\(cleanPlot)")
        }

        let cleanDict = customDictionarySnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanDict.isEmpty {
            sections.append("### Từ điển riêng đã ghi nhận:\n\(cleanDict)")
        }

        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanNotes.isEmpty {
            sections.append("### Ghi chú riêng:\n\(cleanNotes)")
        }

        guard !sections.isEmpty else { return "" }
        return "\n\n[Trí nhớ truyện tích lũy của AI]:\n" + sections.joined(separator: "\n\n")
    }
}
