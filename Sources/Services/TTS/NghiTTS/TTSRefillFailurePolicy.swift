import Foundation

/// Chính sách lỗi khi nạp trước (refill) của engine local — tách khỏi `TTSManager` (đợt 6 tách god object, 1.3.485).
///
/// Toàn bộ là **hàm thuần**, không giữ state: phân loại lỗi, quyết định chặn/thử lại (tối đa `maxAttempts` = 2),
/// chọn ứng viên optional reserve. `TTSManager` giữ `typealias` + forwarder `nonisolated static` cùng chữ ký nên
/// `TTSNextChapterPrefixCache` và `TTSManager+NextChapterPrefix` không phải sửa. Đây là **nguồn duy nhất** cho cả
/// refill Nghi lẫn cache prefix chương kế (luật "retry thuộc đúng một tầng"). `RefillFailureKey` vẫn ở `TTSManager`.
enum TTSRefillFailurePolicy {
    struct RefillFailureState {
        var attempts: Int = 0
        var isBlocked: Bool = false
    }

    enum RefillTaskOutcome: Equatable {
        case success
        case blocked(reason: String, action: String)
        case retryScheduled(reason: String, attempt: Int)
        case cancelled
    }

    static func classifyTTSError(_ error: Error) -> (reason: String, isNonRetryable: Bool) {
        if let ttsError = error as? TTSError {
            switch ttsError {
            case .badRequest:
                return ("badRequest", true)
            case .notFound:
                return ("notFound", true)
            case .modelNotCached:
                return ("modelNotCached", true)
            case .engineUnavailable:
                return ("engineUnavailable", true)
            case .internalError:
                return ("internalError", false)
            }
        }
        return ("unknownError", false)
    }

    static func evaluateRefillError(
        _ error: Error,
        currentAttempts: Int,
        maxAttempts: Int = 2
    ) -> (newState: RefillFailureState, outcome: RefillTaskOutcome) {
        if error is CancellationError {
            return (RefillFailureState(attempts: currentAttempts, isBlocked: false), .cancelled)
        }

        let (reasonCode, isNonRetryable) = classifyTTSError(error)
        if isNonRetryable {
            return (RefillFailureState(attempts: currentAttempts, isBlocked: true), .blocked(reason: reasonCode, action: "blocked_non_retryable"))
        }

        let nextAttempt = currentAttempts + 1
        if nextAttempt >= maxAttempts {
            return (RefillFailureState(attempts: nextAttempt, isBlocked: true), .blocked(reason: reasonCode, action: "blocked_max_retries"))
        } else {
            return (RefillFailureState(attempts: nextAttempt, isBlocked: false), .retryScheduled(reason: reasonCode, attempt: nextAttempt))
        }
    }

    static func selectNghiOptionalRefillCandidate(
        currentParagraphIndex N: Int,
        paragraphsCount: Int,
        preloadedIndices: Set<Int>,
        blockedIndices: Set<Int> = []
    ) -> Int? {
        let optionalStart = N + 2
        guard optionalStart < paragraphsCount else { return nil }
        for idx in optionalStart..<paragraphsCount {
            if !preloadedIndices.contains(idx) && !blockedIndices.contains(idx) {
                return idx
            }
        }
        return nil
    }

    static func logPrefetchFailure(chapter: Int, index: Int, attempt: Int, reason: String, action: String) {
        if AppLogger.shared.isLoggingEnabled {
            AppLogger.shared.log("[TTSPerf] PrefetchFailure chapter=\(chapter) index=\(index) engine=nghitts attempt=\(attempt) reason=\(reason) action=\(action)")
        }
    }
}
