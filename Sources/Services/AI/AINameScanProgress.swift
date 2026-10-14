import Foundation

/// Tiến độ một lần quét tên riêng nhiều chương (1.3.524).
///
/// - `totalBatches == 0`: đang chuẩn bị — đọc các chương đã tải, chưa chia lượt (`chapterCount` có khi đã biết số chương).
/// - `sendingBatch`: lượt **đang gửi** (đánh số từ 1), khớp số tin gửi đi và dòng log `gửi lượt N/T` — trước đây dải
///   tiến độ báo sau khi lượt xong nên chậm một lượt và hiện "Batch 0/1" suốt lượt đầu.
/// - `failedBatches`: số lượt lỗi lẻ đã bỏ qua. Không tính huỷ, không tính lỗi tài khoản/hạn mức (những lỗi đó dừng
///   cả lần quét).
public struct AINameScanProgress: Sendable, Equatable {
    public var sendingBatch: Int
    public var totalBatches: Int
    public var failedBatches: Int
    public var chapterCount: Int?

    public init(sendingBatch: Int = 0, totalBatches: Int = 0, failedBatches: Int = 0, chapterCount: Int? = nil) {
        self.sendingBatch = sendingBatch
        self.totalBatches = totalBatches
        self.failedBatches = failedBatches
        self.chapterCount = chapterCount
    }

    public var isPreparing: Bool { totalBatches == 0 }
}
