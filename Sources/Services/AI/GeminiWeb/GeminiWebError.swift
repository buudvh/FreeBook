import Foundation

/// Lỗi của provider Gemini Web — giao thức web **không chính thức** của gemini.google.com.
///
/// Mọi lỗi đều có mô tả tiếng Việt vì chúng hiện thẳng trong tin nhắn trả lời của màn AI
/// (`"Lỗi phản hồi: \(error.localizedDescription)"`). `protocolChanged` mang vị trí field để người
/// sửa biết Google đổi cấu trúc ở đâu; không có tài liệu chính thức nào cho giao thức này.
public enum GeminiWebError: LocalizedError, Sendable, Equatable {
    /// Trang gemini.google.com chuyển hướng sang đăng nhập hoặc không có token `SNlM0e`.
    case notSignedIn
    /// `GetUserStatus` trả mã khác 1000 (1040/1042 phải chấp nhận điều khoản, 1060 vùng không hỗ trợ…).
    case accountStatus(Int)
    /// Mã 1037: hết hạn mức của model trên tài khoản.
    case usageLimit
    /// Mã 1050/1052: model không khớp hội thoại hoặc header model đã cũ.
    case modelInvalid
    /// Mã 1060 trong khi sinh nội dung: IP bị chặn tạm.
    case ipBlocked
    /// Mã 1013: lỗi tạm của Google, thử lại được.
    case temporary
    case http(Int)
    case protocolChanged(String)
    case timeout
    /// WKWebView ẩn không tạo được hoặc đã bị giải phóng giữa chừng.
    case sessionUnavailable
    /// Tác vụ không hỗ trợ trên Gemini Web (quét tên riêng hàng loạt).
    case unsupportedTask(String)
    /// JavaScript trong trang báo lỗi (fetch bị huỷ, mạng rớt…).
    case script(String)
    /// Stream kết thúc mà không có text. `completed == false`: Google đóng kết nối sớm (thường khi model
    /// suy nghĩ lâu) — thư viện tham chiếu gọi là "silently aborted by Google"; `true`: trả lời rỗng thật
    /// (bộ lọc an toàn…). Trước 1.3.506 trường hợp này bị coi là "thành công rỗng" và màn AI ẩn luôn tin trợ lý.
    case emptyResponse(completed: Bool)
    /// Trang gemini.google.com tự điều hướng sang document mới khi `fetch` đang bay — fetch chết theo document cũ.
    case documentChanged

    public var errorDescription: String? {
        switch self {
        case .emptyResponse(let completed):
            return completed
                ? "Gemini hoàn tất nhưng không trả về nội dung (có thể bị bộ lọc an toàn) — thử diễn đạt lại."
                : "Gemini đóng kết nối trước khi trả lời xong — thử lại hoặc đổi sang model Flash."
        case .documentChanged:
            return "Trang Gemini tự tải lại khi đang trả lời — thử lại."
        case .notSignedIn:
            return "Chưa đăng nhập Google cho Gemini Web — vào Cài đặt › AI › profile Gemini Web để đăng nhập."
        case .accountStatus(let code):
            switch code {
            case 1040, 1042:
                return "Tài khoản Google cần chấp nhận điều khoản Gemini mới — mở gemini.google.com một lần rồi thử lại (mã \(code))."
            case 1060:
                return "Gemini chưa hỗ trợ khu vực của tài khoản này (mã 1060)."
            case 1054, 1057:
                return "Tài khoản bị giới hạn bởi phụ huynh/người giám hộ (mã \(code))."
            default:
                return "Tài khoản Google không dùng được Gemini (mã trạng thái \(code))."
            }
        case .usageLimit:
            return "Hết hạn mức Gemini của tài khoản cho model này — đổi model (vd. Flash) hoặc chờ hạn mức làm mới."
        case .modelInvalid:
            return "Model Gemini Web không hợp lệ hoặc đã đổi — bấm \"Load từ API\" để lấy danh sách model mới."
        case .ipBlocked:
            return "Google tạm chặn địa chỉ IP này — thử mạng khác hoặc chờ một lúc."
        case .temporary:
            return "Gemini gặp lỗi tạm (1013) — thử lại sau vài giây."
        case .http(let status):
            return "Gemini Web trả về HTTP \(status)."
        case .protocolChanged(let detail):
            return "Giao thức Gemini Web có thể đã thay đổi (\(detail))."
        case .timeout:
            return "Gemini Web không phản hồi kịp thời gian chờ."
        case .sessionUnavailable:
            return "Phiên Gemini Web chưa sẵn sàng — thử lại."
        case .unsupportedTask(let task):
            return "Gemini Web không hỗ trợ \(task) — hãy chọn một profile API (Gemini API, OpenAI, Claude…)."
        case .script(let detail):
            return "Lỗi khi gọi Gemini Web trong trang: \(detail)"
        }
    }

    /// Mã lỗi server trong frame `StreamGenerate` (`part[5][2][0][1][0]`).
    public static func fromServerCode(_ code: Int) -> GeminiWebError {
        switch code {
        case 1037: return .usageLimit
        case 1050, 1052: return .modelInvalid
        case 1060: return .ipBlocked
        case 1013: return .temporary
        default: return .protocolChanged("mã lỗi server \(code)")
        }
    }

    /// Trạng thái tài khoản của `GetUserStatus` (`body[14]`): 1000 là bình thường ⇒ `nil`.
    public static func fromAccountStatus(_ code: Int) -> GeminiWebError? {
        switch code {
        case 1000: return nil
        case 1016: return .notSignedIn
        default: return .accountStatus(code)
        }
    }

    /// Thử lại một lần sau khi nghỉ: lỗi tạm 1013, Google cắt stream sớm, trang tự điều hướng.
    public var isRetryable: Bool {
        switch self {
        case .temporary, .documentChanged: return true
        case .emptyResponse(let completed): return !completed
        default: return false
        }
    }

    /// Token `SNlM0e` cũ thường bị trả HTTP 400; đăng nhập hết hạn trả 401/403. Cả hai đáng nạp lại
    /// trang một lần trước khi báo lỗi.
    public var suggestsSessionRefresh: Bool {
        if case .http(let status) = self { return status == 400 || status == 401 || status == 403 }
        return false
    }
}
