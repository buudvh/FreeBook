import Foundation

/// Một lượt (batch) của lần quét tên riêng nhiều chương (1.3.527).
///
/// Là đơn vị gửi của vòng lượt dùng chung trong `AINameExtractionBatchProcessor` (lần quét đầu, lượt tự thử lại ở cuối
/// lần quét, nút "Thử lại k lượt lỗi"), và là thứ coordinator giữ lại **trong RAM** khi lượt đó vẫn lỗi. Giữ số thứ tự
/// gốc để nhãn "lượt N/T" của lần thử lại khớp lượt đã lỗi trong log. Từ 1.3.602 giữ thêm chỉ số chương đầu/cuối của
/// lượt để tính điểm tiếp nối (`AINameScanResumeTracker`).
public struct AINameScanFailedBatch: Sendable, Equatable {
    /// Văn bản raw đã gom của lượt (các chương liền nhau, chưa cắt theo giới hạn ký tự).
    public let text: String
    /// Số thứ tự lượt trong lần quét gốc, đánh số từ 1.
    public let turnIndex: Int
    /// Tổng số lượt của lần quét gốc.
    public let totalTurns: Int
    /// Chỉ số (0-based, theo mục lục) của chương đầu tiên trong lượt.
    public let firstChapterIndex: Int
    /// Chỉ số (0-based, theo mục lục) của chương cuối cùng trong lượt.
    public let lastChapterIndex: Int

    public init(text: String, turnIndex: Int, totalTurns: Int, firstChapterIndex: Int, lastChapterIndex: Int) {
        self.text = text
        self.turnIndex = turnIndex
        self.totalTurns = totalTurns
        self.firstChapterIndex = firstChapterIndex
        self.lastChapterIndex = lastChapterIndex
    }

    /// Nhãn "lượt N/T" gắn vào tin gửi và dòng log.
    public var turnLabel: String { "lượt \(turnIndex)/\(totalTurns)" }
}
