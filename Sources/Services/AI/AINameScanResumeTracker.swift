import Foundation

/// Theo dõi điểm tiếp nối của **một** lần quét tên riêng nhiều chương (1.3.602).
///
/// Luật "dừng trước lượt lỗi" (người dùng chọn): điểm tiếp nối = chỉ số chương cuối của **dãy lượt liên tiếp tính từ
/// lượt 1** đều đã thành công. Lượt lỗi chặn dãy; lượt chưa gửi (bấm Dừng, dừng vì hết hạn mức) không bao giờ được tính.
/// Dãy rỗng (lượt 1 lỗi) ⇒ chương ngay trước lượt 1, tức lần "Tiếp nối" sau bắt đầu lại đúng chỗ lần quét này bắt đầu.
/// Chưa có lượt nào xong (bị dừng/dừng vì hạn mức trước khi lượt 1 xong) ⇒ `nil`: không ghi, điểm cũ được giữ.
///
/// Là **class** dùng chung giữa vòng quét chính, vòng tự thử lại ở cuối và nút "Thử lại k lượt lỗi" (coordinator giữ nó
/// trong `NameScanRetryContext`): lượt thử lại thành công đẩy được dãy đi tiếp. Mỗi lần một lượt xong thì kết quả mới
/// **ghi đè** kết quả cũ của lượt đó: một lượt đã thành công chỉ bị chạy lại khi tên của nó chưa được giữ (lần thử lại
/// bị dừng ngay sau lượt đó, cập nhật bị bỏ) — khi ấy lỗi ở lần chạy lại phải kéo điểm tiếp nối về đúng chỗ. Chỉ tính
/// toán; ghi xuống `AINameScanScopeStore` là việc của coordinator, cùng lúc với danh sách tên của lượt đó.
public final class AINameScanResumeTracker: @unchecked Sendable {
    private let lock = NSLock()
    /// Chương đầu/cuối của từng lượt theo số thứ tự lượt (phần tử 0 = lượt 1).
    private let chapterRanges: [(first: Int, last: Int)]
    private var succeeded: [Bool]
    private var hasCompletedTurn = false

    public init(turns: [AINameScanFailedBatch]) {
        let ordered = turns.sorted { $0.turnIndex < $1.turnIndex }
        self.chapterRanges = ordered.map { (first: $0.firstChapterIndex, last: $0.lastChapterIndex) }
        self.succeeded = Array(repeating: false, count: ordered.count)
    }

    /// Ghi nhận một lượt đã xong (thành công hoặc lỗi) và **không** bị huỷ. Gọi sau kiểm tra huỷ của vòng lượt.
    public func markCompleted(turnIndex: Int, succeeded didSucceed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        hasCompletedTurn = true
        let position = turnIndex - 1
        guard succeeded.indices.contains(position) else { return }
        succeeded[position] = didSucceed
    }

    /// Lượt `turnIndex` thành công ở lần chạy gần nhất của nó chưa — coordinator dùng để bỏ lượt đó khỏi danh sách
    /// "Thử lại k lượt lỗi".
    public func isSucceeded(turnIndex: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let position = turnIndex - 1
        return succeeded.indices.contains(position) && succeeded[position]
    }

    /// Điểm tiếp nối hiện tại theo luật ở đầu file; `nil` = chưa có lượt nào xong.
    public var resumeChapterIndex: Int? {
        lock.lock()
        defer { lock.unlock() }
        guard hasCompletedTurn, let firstRange = chapterRanges.first else { return nil }
        var resume = firstRange.first - 1
        for (position, range) in chapterRanges.enumerated() {
            guard succeeded[position] else { break }
            resume = range.last
        }
        return resume
    }
}
