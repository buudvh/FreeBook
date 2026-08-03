import Foundation

public enum DownloadTaskStatusOutcome: Equatable {
    case completed
    case failed(message: String)
}

public struct DownloadTaskOutcomeCalculator {
    public static func calculateOutcome(
        taskType: TaskType,
        uncachedAttemptCount: Int,
        savedCount: Int,
        failedCount: Int,
        isExportTxtEmpty: Bool
    ) -> DownloadTaskStatusOutcome {
        if taskType == .exportTxt {
            if isExportTxtEmpty || failedCount > 0 {
                return .failed(message: "Xuất file TXT không hoàn chỉnh (Lỗi: \(failedCount) chương, Rỗng: \(isExportTxtEmpty)).")
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
}
