import Foundation

/// Tiến độ một lần quét tên riêng nhiều chương (1.3.524).
///
/// - `totalBatches == 0`: đang chuẩn bị — đọc các chương đã tải, chưa chia lượt (`chapterCount` có khi đã biết số chương,
///   `preparedChapters` = số chương đã đọc xong, báo sau mỗi khối — 1.3.602).
/// - `sendingBatch`: lượt **đang gửi** (đánh số từ 1), khớp số tin gửi đi và dòng log `gửi lượt N/T` — trước đây dải
///   tiến độ báo sau khi lượt xong nên chậm một lượt và hiện "Batch 0/1" suốt lượt đầu.
/// - `failedBatches`: số lượt lỗi lẻ đã bỏ qua. Không tính huỷ, không tính lỗi tài khoản/hạn mức (những lỗi đó dừng
///   cả lần quét).
/// - `isRetry` (1.3.527): đang chạy vòng **thử lại** các lượt lỗi (tự động ở cuối lần quét, hoặc nút "Thử lại k lượt
///   lỗi") — `sendingBatch`/`totalBatches` khi đó đếm trong số lượt đang thử lại; dải tiến độ và widget đổi chữ
///   thành "Đang thử lại".
/// - `resumeChapterIndex` (1.3.602): điểm tiếp nối tính tới lượt vừa xong (`AINameScanResumeTracker`); `nil` = chưa có
///   lượt nào xong. Coordinator chỉ ghi nó xuống `AINameScanScopeStore` **cùng lúc** áp danh sách tên của lượt đó, để
///   điểm tiếp nối không bao giờ vượt quá phần tên đã giữ được.
/// - `rateLimitWaitUntil` (1.3.612): đang chờ Google mở lại giới hạn số câu trả lời AI của Chế độ AI — dải tiến độ đếm
///   ngược tới mốc này, kèm nấc chờ `rateLimitWaitAttempt`/`rateLimitWaitTotal`. `switchedProviderName`: lần quét đã
///   chuyển sang profile Gemini Web này vì Chế độ AI bị giới hạn.
/// - `sendingFirstChapterIndex`…`sendingLastChapterTitle`: các chương của lượt đang gửi (0-based) và tên đã dịch sẵn
///   (vòng lượt dịch một lần mỗi lượt, ngoài main thread); `nil` = chưa gửi lượt nào. Dải tiến độ, tiêu đề tác vụ và
///   toast khi dừng chỉ ghép chuỗi từ các nhãn dựng sẵn bên dưới.
public struct AINameScanProgress: Sendable, Equatable {
    public var sendingBatch: Int
    public var totalBatches: Int
    public var failedBatches: Int
    public var chapterCount: Int?
    public var isRetry: Bool
    public var preparedChapters: Int
    public var resumeChapterIndex: Int?
    public var rateLimitWaitUntil: Date?
    public var rateLimitWaitAttempt: Int
    public var rateLimitWaitTotal: Int
    public var switchedProviderName: String?
    public var sendingFirstChapterIndex: Int?
    public var sendingLastChapterIndex: Int?
    public var sendingFirstChapterTitle: String
    public var sendingLastChapterTitle: String

    public init(
        sendingBatch: Int = 0,
        totalBatches: Int = 0,
        failedBatches: Int = 0,
        chapterCount: Int? = nil,
        isRetry: Bool = false,
        preparedChapters: Int = 0,
        resumeChapterIndex: Int? = nil,
        rateLimitWaitUntil: Date? = nil,
        rateLimitWaitAttempt: Int = 0,
        rateLimitWaitTotal: Int = 0,
        switchedProviderName: String? = nil,
        sendingFirstChapterIndex: Int? = nil,
        sendingLastChapterIndex: Int? = nil,
        sendingFirstChapterTitle: String = "",
        sendingLastChapterTitle: String = ""
    ) {
        self.sendingBatch = sendingBatch
        self.totalBatches = totalBatches
        self.failedBatches = failedBatches
        self.chapterCount = chapterCount
        self.isRetry = isRetry
        self.preparedChapters = preparedChapters
        self.resumeChapterIndex = resumeChapterIndex
        self.rateLimitWaitUntil = rateLimitWaitUntil
        self.rateLimitWaitAttempt = rateLimitWaitAttempt
        self.rateLimitWaitTotal = rateLimitWaitTotal
        self.switchedProviderName = switchedProviderName
        self.sendingFirstChapterIndex = sendingFirstChapterIndex
        self.sendingLastChapterIndex = sendingLastChapterIndex
        self.sendingFirstChapterTitle = sendingFirstChapterTitle
        self.sendingLastChapterTitle = sendingLastChapterTitle
    }

    public var isPreparing: Bool { totalBatches == 0 }

    /// Số giây còn phải chờ giới hạn tại `date`; `nil` = không chờ.
    public func rateLimitRemainingSeconds(at date: Date = Date()) -> Int? {
        guard let until = rateLimitWaitUntil else { return nil }
        return max(0, Int(until.timeIntervalSince(date).rounded(.up)))
    }

    // MARK: - Nhãn chương của lượt đang gửi (số chương đánh từ 1)

    /// Số chương (đánh từ 1) đầu/cuối của lượt đang gửi; `nil` = chưa gửi lượt nào.
    private var sendingChapterNumbers: (first: Int, last: Int)? {
        guard let first = sendingFirstChapterIndex else { return nil }
        return (first + 1, max(first, sendingLastChapterIndex ?? first) + 1)
    }

    /// "ch.21–30" (nhiều chương) hoặc "ch.21" (một chương) — đuôi tiêu đề tác vụ.
    public var sendingChapterRangeLabel: String? {
        guard let numbers = sendingChapterNumbers else { return nil }
        return numbers.first == numbers.last ? "ch.\(numbers.first)" : "ch.\(numbers.first)–\(numbers.last)"
    }

    /// Phần chương trên tiêu đề dải tiến độ: một chương ⇒ "ch.21: tên" (không có dòng tên riêng); nhiều chương ⇒
    /// "ch.21–30" (tên nằm ở `sendingChapterNamesLine`).
    public var sendingChapterHeadline: String? {
        guard let numbers = sendingChapterNumbers, let range = sendingChapterRangeLabel else { return nil }
        guard numbers.first == numbers.last, !sendingFirstChapterTitle.isEmpty else { return range }
        return "\(range): \(sendingFirstChapterTitle)"
    }

    /// Dòng tên dưới tiêu đề — chỉ lượt nhiều chương: "ch.21 tên → ch.30 tên"; chương nào không có tên thì chỉ số
    /// chương; không chương nào có tên ⇒ `nil`.
    public var sendingChapterNamesLine: String? {
        guard let numbers = sendingChapterNumbers, numbers.first != numbers.last else { return nil }
        guard !sendingFirstChapterTitle.isEmpty || !sendingLastChapterTitle.isEmpty else { return nil }
        let head = sendingFirstChapterTitle.isEmpty ? "ch.\(numbers.first)" : "ch.\(numbers.first) \(sendingFirstChapterTitle)"
        let tail = sendingLastChapterTitle.isEmpty ? "ch.\(numbers.last)" : "ch.\(numbers.last) \(sendingLastChapterTitle)"
        return "\(head) → \(tail)"
    }

    /// Nhãn chương của toast khi dừng: "ch.21–30: tên ch.21 → tên ch.30" hoặc "ch.21: tên"; chương nào không có tên thì
    /// thay bằng số chương, không chương nào có tên ⇒ chỉ khoảng chương; chưa gửi lượt nào ⇒ `nil`.
    public var sendingChapterToastLabel: String? {
        guard let numbers = sendingChapterNumbers, let range = sendingChapterRangeLabel else { return nil }
        if numbers.first == numbers.last { return sendingChapterHeadline }
        guard !sendingFirstChapterTitle.isEmpty || !sendingLastChapterTitle.isEmpty else { return range }
        let head = sendingFirstChapterTitle.isEmpty ? "ch.\(numbers.first)" : sendingFirstChapterTitle
        let tail = sendingLastChapterTitle.isEmpty ? "ch.\(numbers.last)" : sendingLastChapterTitle
        return "\(range): \(head) → \(tail)"
    }
}
