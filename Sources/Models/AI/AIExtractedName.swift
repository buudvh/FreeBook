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

    public init(
        id: UUID = UUID(),
        original: String,
        suggestedMeaning: String,
        category: String = "Nhân vật",
        occurrenceCount: Int = 1,
        isSelected: Bool = true
    ) {
        self.id = id
        self.original = original
        self.suggestedMeaning = suggestedMeaning
        self.category = category
        self.occurrenceCount = occurrenceCount
        self.isSelected = isSelected
    }
}
