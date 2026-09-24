import Foundation

/// Đại diện cho một tên riêng được AI trích xuất từ văn bản chương truyện.
public struct AIExtractedName: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    /// Tên gốc Hán tự tiếng Trung (ví dụ: 萧炎, 乌坦城)
    public var original: String
    /// Nghĩa đề xuất (Phiên âm Hán-Việt hoặc nghĩa dịch, ví dụ: Tiêu Viêm, Ô Thản Thành)
    public var suggestedMeaning: String
    /// Phân loại (Nhân vật, Địa danh, Tông môn, Công pháp, Bảo vật, Khác)
    public var category: String
    /// Số lần xuất hiện trong văn bản quét
    public var occurrenceCount: Int
    /// Trạng thái checkbox được chọn để lưu vào từ điển truyện
    public var isSelected: Bool
    /// Đã tồn tại trong từ điển Name riêng (Names.txt) của truyện
    public var hasInBookNames: Bool
    /// Đã tồn tại trong từ điển VietPhrase riêng (VietPhrase.txt) của truyện
    public var hasInBookVP: Bool

    public init(
        id: UUID = UUID(),
        original: String,
        suggestedMeaning: String,
        category: String = "Nhân vật",
        occurrenceCount: Int = 1,
        isSelected: Bool = true,
        hasInBookNames: Bool = false,
        hasInBookVP: Bool = false
    ) {
        self.id = id
        self.original = original
        self.suggestedMeaning = suggestedMeaning
        self.category = category
        self.occurrenceCount = occurrenceCount
        self.isSelected = isSelected
        self.hasInBookNames = hasInBookNames
        self.hasInBookVP = hasInBookVP
    }

    enum CodingKeys: String, CodingKey {
        case id, original, suggestedMeaning, category, occurrenceCount, isSelected
        case hasInBookNames, hasInBookVP
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.original = try container.decodeIfPresent(String.self, forKey: .original) ?? ""
        self.suggestedMeaning = try container.decodeIfPresent(String.self, forKey: .suggestedMeaning) ?? ""
        self.category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Nhân vật"
        self.occurrenceCount = try container.decodeIfPresent(Int.self, forKey: .occurrenceCount) ?? 1
        self.isSelected = try container.decodeIfPresent(Bool.self, forKey: .isSelected) ?? true
        self.hasInBookNames = try container.decodeIfPresent(Bool.self, forKey: .hasInBookNames) ?? false
        self.hasInBookVP = try container.decodeIfPresent(Bool.self, forKey: .hasInBookVP) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(original, forKey: .original)
        try container.encode(suggestedMeaning, forKey: .suggestedMeaning)
        try container.encode(category, forKey: .category)
        try container.encode(occurrenceCount, forKey: .occurrenceCount)
        try container.encode(isSelected, forKey: .isSelected)
        try container.encode(hasInBookNames, forKey: .hasInBookNames)
        try container.encode(hasInBookVP, forKey: .hasInBookVP)
    }
}
