import Foundation

/// Lỗi của provider ChatGPT Web (trang `chatgpt.com`, ẩn danh hoặc đã đăng nhập, 1.3.971) — trang web **không** có API
/// chính thức.
///
/// Mô tả tiếng Việt vì chúng hiện thẳng trong tin trả lời của màn AI (`"Lỗi phản hồi: …"`, `"Lỗi quét tên riêng: …"`) và
/// trong kết quả "Kiểm tra kết nối". `openBrowserMarker` là chuỗi cố định nằm trong mô tả của các lỗi mà người dùng phải
/// tự xử lý trên trang ChatGPT: View dò nó trong nội dung tin để hiện nút "Mở ChatGPT" (cùng lý do với
/// `GoogleAIModeError.captchaMarker` — không thêm field vào `AIChatMessage`).
public enum ChatGPTWebError: LocalizedError, Sendable, Equatable {
    /// Trang kiểm tra của Cloudflare ("Just a moment…") không tự qua sau thời gian chờ.
    case captchaRequired
    /// Hộp mời đăng nhập của ChatGPT đang mở và lượt gửi không bắt đầu (ChatGPT bật hộp này sau 5 tin ẩn danh).
    case loginPrompt
    /// ChatGPT bắt đăng nhập mới cho hỏi tiếp (cổng `force_login`).
    case loginRequired
    /// ChatGPT báo hết lượt hỏi ẩn danh (cổng `rate_limited`), hoặc app còn trong hạn chờ sau lần báo đó. `retryAfter`
    /// (giây, 0 = trang không cho biết) — **không bao giờ** gửi lại ngay.
    case rateLimited(retryAfter: Int)
    /// Cổng chặn khác của trang (`forbidden`…), kèm chữ trang hiện.
    case blocked(String)
    /// Trang hiện "Chat stopped unexpectedly" (hoặc thông báo lỗi gửi khác).
    case generationFailed(String)
    /// Prompt vượt ngân sách độ dài của app.
    case requestTooLong
    /// Lượt trả lời xong mà không có chữ.
    case emptyResponse
    case timeout
    case pageLoadFailed(String)
    /// Trang không còn giữ cuộc chat của phiên (đã đưa về trang trắng, lượt khác đã điều hướng…) — chat thường mở cuộc
    /// chat mới với đủ ngữ cảnh.
    case threadUnavailable
    /// Trang đổi cấu trúc: không thấy ô nhập, không thấy lượt trả lời…
    case protocolChanged(String)
    /// WKWebView ẩn bị giải phóng giữa chừng (tiến trình web bị kết thúc…).
    case webViewUnavailable
    /// Lượt quét tên riêng bị app vào nền cắt quá số lần gửi lại cho phép (`HiddenWebForegroundRunner`).
    case interruptedInBackground

    /// Chuỗi cố định trong mô tả của các lỗi cần người dùng tự mở trang ChatGPT — màn AI và màn Cấu hình AI dò chuỗi này
    /// để hiện nút "Mở ChatGPT".
    public static let openBrowserMarker = "mở ChatGPT trong trình duyệt của app"

    public var errorDescription: String? {
        switch self {
        case .captchaRequired:
            return "ChatGPT đang kiểm tra trình duyệt (Cloudflare) — \(Self.openBrowserMarker) để qua bước kiểm tra rồi thử lại."
        case .loginPrompt:
            return "ChatGPT đang hiện hộp mời đăng nhập nên chưa gửi được — thử lại, hoặc \(Self.openBrowserMarker) để đăng nhập."
        case .loginRequired:
            return "ChatGPT yêu cầu đăng nhập mới cho hỏi tiếp (hết phần dùng ẩn danh) — \(Self.openBrowserMarker) để đăng nhập rồi thử lại."
        case .rateLimited(let retryAfter):
            let when = retryAfter > 0 ? "thử lại sau \(GoogleAIModeError.clockText(seconds: retryAfter))" : "thử lại sau"
            return "ChatGPT báo đã hết lượt hỏi — \(when), hoặc \(Self.openBrowserMarker) để xem (đăng nhập thì hạn mức theo tài khoản)."
        case .blocked(let detail):
            return "ChatGPT chặn lượt hỏi (\(detail)) — \(Self.openBrowserMarker) để xem."
        case .generationFailed(let detail):
            return "ChatGPT báo lỗi, không tạo được câu trả lời (\(detail)) — thử lại."
        case .requestTooLong:
            return "Nội dung quá dài cho ChatGPT Web — rút ngắn tin nhắn hoặc prompt."
        case .emptyResponse:
            return "ChatGPT không trả về nội dung — thử diễn đạt lại."
        case .timeout:
            return "ChatGPT không phản hồi kịp thời gian chờ."
        case .pageLoadFailed(let detail):
            return "Không tải được trang ChatGPT: \(detail)"
        case .threadUnavailable:
            return "Trang ChatGPT không còn giữ cuộc chat cũ."
        case .protocolChanged(let detail):
            return "Trang ChatGPT có thể đã thay đổi (\(detail))."
        case .webViewUnavailable:
            return "Trình duyệt ẩn của ChatGPT Web chưa sẵn sàng — thử lại."
        case .interruptedInBackground:
            return "Lượt gửi ChatGPT Web bị gián đoạn vì app vào nền nhiều lần — để app mở trong lúc quét rồi thử lại."
        }
    }

    /// Thử lại một lần (chỉ khi chưa phát chữ nào): trang trả rỗng.
    public var isRetryable: Bool {
        self == .emptyResponse
    }

    public var isRateLimit: Bool {
        if case .rateLimited = self { return true }
        return false
    }

    /// Lỗi khiến quét tên riêng nhiều chương phải dừng cả lần quét: gọi tiếp chỉ làm ChatGPT chặn nặng hơn (hết lượt, bắt
    /// đăng nhập, kiểm tra trình duyệt) hoặc lượt nào cũng lỗi y hệt (prompt quá dài).
    public var stopsNameScan: Bool {
        switch self {
        case .captchaRequired, .loginPrompt, .loginRequired, .rateLimited, .blocked, .requestTooLong:
            return true
        default:
            return false
        }
    }
}
