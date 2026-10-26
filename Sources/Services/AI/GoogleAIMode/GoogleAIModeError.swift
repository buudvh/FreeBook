import Foundation

/// Lỗi của provider Chế độ AI của Google (`google.com/search?udm=50`, 1.3.609) — trang web **không** có API chính thức.
///
/// Mô tả tiếng Việt vì chúng hiện thẳng trong tin trả lời của màn AI (`"Lỗi phản hồi: …"`, `"Lỗi quét tên riêng: …"`) và
/// trong kết quả "Kiểm tra kết nối". `captchaMarker` là chuỗi cố định nằm trong mô tả của `captchaRequired`: View dò nó
/// trong nội dung tin để hiện nút "Mở Google để xác minh" — không thêm field vào `AIChatMessage` vì phiên có hai nơi ghi
/// (View và `AIRuntimeCoordinator`), field mới dễ bị bên kia ghi đè mất.
public enum GoogleAIModeError: LocalizedError, Sendable, Equatable {
    /// Google chuyển sang trang `/sorry` (nghi bot) hoặc trả HTTP 429.
    case captchaRequired
    /// Lượt mới nhất của trang hiện "Đã xảy ra lỗi nên không tạo được nội dung."
    case generationFailed
    /// Câu hỏi vượt giới hạn độ dài (URL ~64 KB / ô nhập 8.192 ký tự) — HTTP 413 hoặc ngân sách của app.
    case requestTooLong
    /// Lượt trả lời xong mà không có chữ.
    case emptyResponse
    case timeout
    case pageLoadFailed(String)
    /// Không mở lại được cuộc chat cũ (khôi phục bằng `mstk` không ra lượt nào, hoặc không có ô hỏi tiếp) — chat thường
    /// mở cuộc chat mới với đủ ngữ cảnh.
    case threadUnavailable
    /// Trang đổi cấu trúc: không thấy khối lượt, phần trả lời lẫn câu hỏi…
    case protocolChanged(String)
    /// WKWebView ẩn bị giải phóng giữa chừng (tiến trình web bị kết thúc…).
    case webViewUnavailable
    /// Lượt quét tên riêng bị app vào nền cắt quá số lần gửi lại cho phép (`HiddenWebForegroundRunner`).
    case interruptedInBackground
    /// Google báo "đã đạt đến giới hạn về số lượng yêu cầu đối với câu trả lời của AI" (1.3.612), hoặc app còn đang trong
    /// hạn chờ sau lần báo đó (`GoogleAIModeTurnQueue`) — **không bao giờ** gửi lại ngay. `retryAfter` (giây, 0 = chưa rõ)
    /// là hạn chờ còn lại.
    case rateLimited(retryAfter: Int)
    /// Quét tên riêng đã chờ đủ các lần (1 → 2 → 4 → 8 phút) mà Google vẫn giới hạn, và không có profile Gemini Web để
    /// chuyển sang — dừng lần quét, giữ tên và điểm tiếp nối.
    case rateLimitExhausted(waitedMinutes: Int)

    /// Chuỗi cố định trong mô tả của `captchaRequired` — màn AI và màn Cấu hình AI dò chuỗi này để hiện nút xác minh.
    public static let captchaMarker = "Google cần xác minh bạn không phải robot"
    /// Chuỗi cố định trong mô tả của `rateLimited` (1.3.612).
    public static let rateLimitMarker = "Google tạm giới hạn số câu trả lời AI"

    /// "1:45" — đếm ngược của hạn chờ, dùng chung cho thông điệp lỗi, dải tiến độ và tiêu đề tác vụ.
    public static func clockText(seconds: Int) -> String {
        let value = max(0, seconds)
        return "\(value / 60):" + String(format: "%02d", value % 60)
    }

    public var errorDescription: String? {
        switch self {
        case .captchaRequired:
            return "\(Self.captchaMarker) (captcha) — bấm \"Mở Google để xác minh\", giải xong rồi thử lại."
        case .generationFailed:
            return "Chế độ AI của Google báo lỗi, không tạo được câu trả lời — thử lại."
        case .requestTooLong:
            return "Nội dung quá dài cho Chế độ AI của Google (Google giới hạn độ dài câu hỏi) — rút ngắn tin nhắn hoặc prompt."
        case .emptyResponse:
            return "Chế độ AI của Google không trả về nội dung — thử diễn đạt lại."
        case .timeout:
            return "Chế độ AI của Google không phản hồi kịp thời gian chờ."
        case .pageLoadFailed(let detail):
            return "Không tải được trang Google: \(detail)"
        case .threadUnavailable:
            return "Không mở lại được cuộc chat Chế độ AI cũ."
        case .protocolChanged(let detail):
            return "Trang Chế độ AI của Google có thể đã thay đổi (\(detail))."
        case .webViewUnavailable:
            return "Trình duyệt ẩn của Chế độ AI chưa sẵn sàng — thử lại."
        case .interruptedInBackground:
            return "Lượt gửi Chế độ AI bị gián đoạn vì app vào nền nhiều lần — để app mở trong lúc quét rồi thử lại."
        case .rateLimited(let retryAfter):
            let when = retryAfter > 0 ? "thử lại sau \(Self.clockText(seconds: retryAfter))" : "thử lại sau ít phút"
            return "\(Self.rateLimitMarker) — \(when)."
        case .rateLimitExhausted(let waitedMinutes):
            return "Google giới hạn số câu trả lời AI, đã chờ \(waitedMinutes) phút vẫn chưa mở. Quét lại bằng \"Tiếp nối\" để đi tiếp từ chỗ dừng."
        }
    }

    /// Thử lại một lần (chỉ khi chưa phát chữ nào): trang trả rỗng. **Không** gồm `generationFailed` (1.3.612): người
    /// dùng gặp đúng lỗi này khi Google giới hạn số câu trả lời AI — gửi lại ngay chỉ đốt thêm hạn mức.
    public var isRetryable: Bool {
        switch self {
        case .emptyResponse: return true
        default: return false
        }
    }

    public var isRateLimit: Bool {
        if case .rateLimited = self { return true }
        return false
    }

    /// Lỗi khiến quét tên riêng nhiều chương phải dừng cả lần quét: gọi tiếp chỉ làm Google chặn nặng hơn (captcha, đã
    /// chờ hết các lần mà vẫn bị giới hạn) hoặc lượt nào cũng lỗi y hệt (prompt quá dài). `rateLimited` không nằm đây:
    /// vòng quét tự chuyển Gemini Web hoặc tự chờ (`AINameExtractionBatchProcessor+RateLimit`).
    public var stopsNameScan: Bool {
        switch self {
        case .captchaRequired, .requestTooLong, .rateLimitExhausted: return true
        default: return false
        }
    }
}
