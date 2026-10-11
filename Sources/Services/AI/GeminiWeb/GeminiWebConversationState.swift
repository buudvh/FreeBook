import Foundation

/// Cuộc chat Gemini gắn với **một phiên chat của app** (1.3.514).
///
/// Gemini nối tiếp hội thoại bằng metadata 10 ô gửi vào `f.req[2]`: `[0]` cid, `[1]` rid, `[2]` rcid, …, `[9]`
/// chuỗi ngữ cảnh. Sau mỗi lượt, phản hồi trả cid/rid (`inner[1]`), rcid (ứng viên `[0]`) và ngữ cảnh (`inner[25]`);
/// chỉ ghi đè ô có giá trị (port setter `ChatSession.metadata` của `gemini-webapi`). Đã thử thật: lượt 2 kèm
/// metadata của lượt 1 ⇒ Gemini nhớ nội dung lượt 1, cùng cid — đúng cả với chat tạm lẫn chat lưu lịch sử.
struct GeminiWebConversationState: Codable, Sendable, Equatable {
    static let emptyMetadata: [String?] = ["", "", "", nil, nil, nil, nil, nil, nil, ""]

    var metadata: [String?]
    /// Model của cuộc chat — đổi model giữa chừng Google trả 1050 (`MODEL_INCONSISTENT`) ⇒ mở cuộc chat mới.
    var model: String
    /// Băm khối ngữ cảnh hệ thống đã gửi gần nhất — đổi (sang chương khác, đổi chế độ…) thì gửi kèm "Cập nhật ngữ cảnh".
    var contextFingerprint: String
    /// Cuộc chat mở ở chế độ lưu lịch sử hay chat tạm — đổi công tắc thì mở cuộc chat mới.
    var savedToHistory: Bool
    var updatedAt: Date

    var cid: String { metadata.first.flatMap { $0 } ?? "" }

    init(model: String, contextFingerprint: String, savedToHistory: Bool) {
        self.metadata = Self.emptyMetadata
        self.model = model
        self.contextFingerprint = contextFingerprint
        self.savedToHistory = savedToHistory
        self.updatedAt = Date()
    }

    /// Ghép cập nhật của một envelope: chỉ ô có giá trị mới ghi đè.
    mutating func apply(_ update: GeminiWebResponseParser.ConversationUpdate) {
        if metadata.count < 10 {
            metadata += Array(repeating: nil, count: 10 - metadata.count)
        }
        for (index, value) in update.ids.prefix(10).enumerated() {
            if let value { metadata[index] = value }
        }
        if let rcid = update.rcid { metadata[2] = rcid }
        if let context = update.context { metadata[9] = context }
    }
}
