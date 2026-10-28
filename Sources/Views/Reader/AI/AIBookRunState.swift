import Foundation

/// Trạng thái AI của **một** truyện trong `AIRuntimeCoordinator.runs`, khoá theo `bookId` (1.3.558).
///
/// Trước 1.3.558 coordinator chỉ có một ô trạng thái cho cả app: quét truyện A thì màn AI của truyện B cũng hiện
/// dải quét của A và bị khoá, bấm dừng ở B còn huỷ luôn lượt quét của A. Nay mỗi truyện một entry: truyện không có
/// entry ⇒ không chạy gì, màn AI của nó không bị tác vụ của truyện khác chạm tới.
///
/// Entry chỉ sống khi truyện đang chạy, khi còn lượt quét lỗi chờ nút "Thử lại k lượt lỗi", hoặc khi kết quả đã xong
/// mà người dùng chưa xem (`unseenOutcome`, 1.3.630) — hai trường hợp sau `isRunning == false` và không giữ `session`
/// (xem `AIRuntimeCoordinator.endRun`).
public struct AIBookRunState: Equatable {
    public let bookId: String
    public var bookTitle: String
    public var isRunning: Bool
    /// Tác vụ đang làm, hiện ở trang "Tác vụ AI" của nút nổi ("AI đang suy nghĩ", "Đang quét: Batch N/T").
    public var taskTitle: String
    /// Mốc bắt đầu lượt hiện hành — nút nổi xếp truyện bắt đầu gần nhất lên đầu.
    public var startedAt: Date
    /// Phiên chat mà tác vụ đang ghi vào (stream ghi mỗi ≥ 50 ms).
    public var session: AIChatSession?
    public var batchProgress: AINameScanProgress?
    public var batchExtractedNames: [AIExtractedName]
    public var nameScanRetry: AIRuntimeCoordinator.NameScanRetryInfo?
    /// Kết quả đã xong trong lúc màn AI của truyện đóng, chưa ai xem (1.3.630) — nút hub giữ dòng "bấm để xem".
    public var unseenOutcome: AIUnseenResult.Outcome?
    /// Mốc xong của kết quả chưa xem — trang "Tác vụ AI" xếp kết quả xong gần nhất lên đầu nhóm chưa xem.
    public var finishedAt: Date?

    init(bookId: String, bookTitle: String, taskTitle: String, session: AIChatSession?) {
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.isRunning = true
        self.taskTitle = taskTitle
        self.startedAt = Date()
        self.session = session
        self.batchProgress = nil
        self.batchExtractedNames = []
        self.nameScanRetry = nil
        self.unseenOutcome = nil
        self.finishedAt = nil
    }
}
