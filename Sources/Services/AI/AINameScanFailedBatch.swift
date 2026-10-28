import Foundation

/// Một lượt (batch) của lần quét tên riêng nhiều chương (1.3.527).
///
/// Là đơn vị gửi của vòng lượt dùng chung trong `AINameExtractionBatchProcessor` (lần quét đầu, lượt tự thử lại ở cuối
/// lần quét, nút "Thử lại k lượt lỗi"), và là thứ coordinator giữ lại **trong RAM** khi lượt đó vẫn lỗi. Giữ số thứ tự
/// gốc để nhãn "lượt N/T" của lần thử lại khớp lượt đã lỗi trong log. Từ 1.3.602 giữ thêm chỉ số chương đầu/cuối của
/// lượt để tính điểm tiếp nối (`AINameScanResumeTracker`). Giữ thêm chương cuối để hiển thị và tên gốc chương đầu/cuối
/// — dải tiến độ, tiêu đề tác vụ và toast khi dừng báo lượt đang gửi gồm những chương nào.
public struct AINameScanFailedBatch: Sendable, Equatable {
    /// Văn bản raw đã gom của lượt (các chương liền nhau, chưa cắt theo giới hạn ký tự).
    public let text: String
    /// Số thứ tự lượt trong lần quét gốc, đánh số từ 1.
    public let turnIndex: Int
    /// Tổng số lượt của lần quét gốc.
    public let totalTurns: Int
    /// Chỉ số (0-based, theo mục lục) của chương đầu tiên trong lượt.
    public let firstChapterIndex: Int
    /// Chỉ số (0-based, theo mục lục) của chương cuối cùng trong lượt — nghĩa **điểm tiếp nối**: chương cuối nằm trọn
    /// trong phần được gửi, có thể nhỏ hơn `firstChapterIndex` (lượt Chế độ AI chỉ chứa mảnh giữa chương).
    public let lastChapterIndex: Int
    /// Chương cuối **có chữ** trong phần được gửi (0-based, luôn ≥ `firstChapterIndex`) — chỉ để hiển thị.
    public let displayLastChapterIndex: Int
    /// Tên gốc của chương đầu và chương `displayLastChapterIndex` (`title` đã trim, rỗng thì `titleTrans`); rỗng = không
    /// có tên. Dịch lúc gửi lượt (`AINameScanChapterTitleStyle`).
    public let firstChapterTitle: String
    public let lastChapterTitle: String

    public init(
        text: String,
        turnIndex: Int,
        totalTurns: Int,
        firstChapterIndex: Int,
        lastChapterIndex: Int,
        displayLastChapterIndex: Int? = nil,
        firstChapterTitle: String = "",
        lastChapterTitle: String = ""
    ) {
        self.text = text
        self.turnIndex = turnIndex
        self.totalTurns = totalTurns
        self.firstChapterIndex = firstChapterIndex
        self.lastChapterIndex = lastChapterIndex
        self.displayLastChapterIndex = max(firstChapterIndex, displayLastChapterIndex ?? lastChapterIndex)
        self.firstChapterTitle = firstChapterTitle
        self.lastChapterTitle = lastChapterTitle
    }

    /// Nhãn "lượt N/T" gắn vào tin gửi và dòng log.
    public var turnLabel: String { "lượt \(turnIndex)/\(totalTurns)" }
}
