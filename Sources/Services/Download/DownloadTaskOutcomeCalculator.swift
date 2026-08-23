import Foundation

public enum DownloadTaskStatusOutcome: Equatable {
    case completed
    case failed(message: String)
}

/// Chính sách kết thúc của một tác vụ tải/xuất — nơi **duy nhất** quyết định `completed` hay `failed`.
///
/// Từ 1.3.253 tác vụ xuất theo chính sách "xuất những gì có": trước đây **một** chương lỗi là bỏ cả file
/// (`failedCount > 0` ⇒ `.failed`), người dùng mất luôn 900 chương đã tải được; còn khi bật "Chỉ xuất chương
/// đã tải" thì file thiếu chương lại được báo `completed` mà không nói thiếu bao nhiêu. Nay: không render
/// được chương nào ⇒ `.failed`; render được ⇒ `.completed` kèm `exportSummary` nói rõ `đã xuất/thiếu/lỗi`.
public struct DownloadTaskOutcomeCalculator {
    public static func calculateOutcome(
        isExport: Bool,
        uncachedAttemptCount: Int,
        savedCount: Int,
        failedCount: Int,
        skippedUncachedCount: Int,
        renderedChapterCount: Int
    ) -> DownloadTaskStatusOutcome {
        if isExport {
            if renderedChapterCount == 0 {
                return .failed(
                    message: "Không xuất được chương nào (lỗi \(failedCount) chương, chưa tải \(skippedUncachedCount) chương)."
                )
            }
            return .completed
        }

        if uncachedAttemptCount == 0 {
            return .completed
        }

        if uncachedAttemptCount > 0 {
            if savedCount == 0 {
                return .failed(message: "Không thể tải chương mới nào (Thất bại: \(failedCount)).")
            }
            if failedCount > 0 {
                return .failed(message: "Tải không hoàn chỉnh: Đã lưu \(savedCount) chương, Thất bại \(failedCount) chương.")
            }
            return .completed
        }

        return .failed(message: "Không thể tải chương mới nào.")
    }

    /// Dòng tổng kết hiện trên trình theo dõi. `nil` khi bản xuất đủ chương — không cần nói gì thêm.
    public static func exportSummary(
        plannedCount: Int,
        renderedChapterCount: Int,
        skippedUncachedCount: Int,
        failedCount: Int
    ) -> String? {
        guard renderedChapterCount > 0 else { return nil }
        if skippedUncachedCount == 0 && failedCount == 0 {
            return nil
        }
        return "Đã xuất \(renderedChapterCount)/\(plannedCount) chương (thiếu \(skippedUncachedCount), lỗi \(failedCount))"
    }
}
