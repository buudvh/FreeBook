import Foundation

/// Một prompt tự nhập đã lưu của sheet "Quét tên riêng theo phạm vi" (Gần đây theo truyện hoặc Đã ghim dùng chung) —
/// chỉ là chữ người dùng gõ trong ô "Prompt cho lần này", không bao giờ kèm nội dung truyện. Kho: `AINameScanPromptStore`.
public struct AINameScanSavedPrompt: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    /// Đã cắt khoảng trắng hai đầu — so trùng bằng đúng chuỗi này.
    public let text: String
    /// Lần quét gần nhất dùng prompt này (Gần đây) / lúc ghim (Đã ghim).
    public var lastUsedAt: Date

    public init(id: UUID = UUID(), text: String, lastUsedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.lastUsedAt = lastUsedAt
    }

    /// Số dòng có chữ — phụ đề "N dòng" của trang "Prompt đã lưu".
    public var lineCount: Int {
        text.split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }
}
