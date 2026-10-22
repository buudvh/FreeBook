import Foundation

/// Kết luận "lỗi do ai" cho một nguồn Legado **lỗi** (màn Kiểm tra nguồn, Gỡ lỗi từng bước, báo cáo nghiệm thu).
/// Do `LegadoFailureArbiter.judge` quyết định — một nguồn sự thật cho cả bộ chạy hàng loạt lẫn màn gỡ lỗi.
///
/// `rawValue` đi vào báo cáo JSON (`SourceResult.verdict`, `byVerdict`) — đổi tên là vỡ client cũ.
public enum LegadoFailureVerdict: String, Codable, Sendable, CaseIterable {
    /// Web chặn / sập: mạng, DNS, quá thời gian, HTTP 403/410/429/451/5xx, trang chặn theo vùng / từ chối truy cập.
    case web
    /// Nguồn lỗi thời: trang tải được nhưng không còn phần tử mà rule nhắm tới, hoặc nguồn thiếu rule.
    case sourceOutdated
    /// Cần xác minh / đăng nhập: captcha, thử thách Cloudflare, nguồn cần đăng nhập, cần mở trình duyệt.
    case needsUser
    /// Nghi do app: cú pháp/hàm chưa hỗ trợ, lỗi phần giả lập của app, hoặc trang có phần tử đúng rule mà engine ra 0.
    case app
    /// Chưa rõ: không đủ bằng chứng (lỗi JS của chính script nguồn, rule toàn JS/JSON…).
    case unknown

    /// Nhãn hiển thị.
    var label: String {
        switch self {
        case .web: return "Web chặn / sập"
        case .sourceOutdated: return "Nguồn lỗi thời"
        case .needsUser: return "Cần xác minh / đăng nhập"
        case .app: return "Nghi do app"
        case .unknown: return "Chưa rõ"
        }
    }
}
