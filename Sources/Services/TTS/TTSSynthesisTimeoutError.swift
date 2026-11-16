import Foundation

/// Lỗi **hết giờ** khi tổng hợp giọng online (1.3.953).
///
/// Không phải lỗi mạng gốc: đây là lỗi **do app chủ động cắt** lượt tổng hợp quá thời gian cho phép
/// (`TTSOnlineSynthesisSettings.effectiveTimeoutSeconds`). Cần phân biệt vì "lượt nạp trước hụt timeout"
/// là tín hiệu server chết chung ⇒ bật giọng dự phòng ngay, còn lỗi khác (voice sai, base64 hỏng) thì không.
internal enum TTSSynthesisTimeoutError: LocalizedError {
    case timedOut(seconds: Int)

    var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "TTS online không phản hồi trong \(seconds) giây"
        }
    }
}
