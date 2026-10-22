import Foundation

/// Dấu hiệu "trang này không phải nội dung của nguồn" trong thân phản hồi: thử thách/captcha (cần người dùng) hoặc
/// trang chặn của máy chủ (web chặn). Dùng chung cho đầu dò bộ chọn (thân đầy đủ) và bộ phân xử (đoạn đầu 4 KB của
/// vết request). Chỉ đọc **16 KB đầu** của thân — các trang này nhỏ, dấu hiệu nằm ở `<title>`/đầu trang.
///
/// Dấu hiệu yếu (chữ "captcha", "安全验证", "Access denied"…) chỉ tính khi nằm trong `<title>`, khi mã HTTP ≥ 400 hoặc khi
/// trang rất nhỏ — trang thường có script reCAPTCHA hay chữ "Access denied" trong bài viết không bị bắt nhầm.
enum LegadoPageMarker: String, Sendable, Equatable, Codable {
    /// Thử thách Cloudflare ("Just a moment…", `cf-chl`, `challenge-platform`, "Attention Required").
    case cloudflareChallenge
    /// Trang captcha / xác minh người thật ("captcha", "安全验证", "人机验证").
    case captcha
    /// Chặn theo vùng ("你的区域被禁止访问", trang chặn của 1Panel).
    case regionBlocked
    /// Trang từ chối truy cập ("访问被拒绝", "Access denied", "403 Forbidden").
    case accessDenied

    /// Cần người dùng (mở trình duyệt / đăng nhập / giải captcha) chứ không phải web hỏng.
    var needsUser: Bool {
        self == .cloudflareChallenge || self == .captcha
    }

    /// Lý do ngắn cho câu kết luận.
    var reason: String {
        switch self {
        case .cloudflareChallenge: return "thử thách Cloudflare"
        case .captcha: return "trang yêu cầu captcha / xác minh"
        case .regionBlocked: return "chặn theo vùng"
        case .accessDenied: return "web từ chối truy cập"
        }
    }

    static let scanLimit = 16_384
    /// Trang nhỏ hơn mức này mà có chữ "captcha"/"Access denied" thì coi là trang chặn.
    static let smallPageBytes = 6_000

    /// Dấu hiệu đầu tiên tìm thấy (ưu tiên cần-người-dùng trước web chặn), `nil` khi không có.
    /// - Parameters:
    ///   - body: thân phản hồi (đủ hoặc đoạn đầu).
    ///   - statusCode: mã HTTP (`nil` khi không có phản hồi).
    ///   - byteCount: kích thước thật của thân (đoạn đầu có thể bị cắt).
    static func detect(body: String, statusCode: Int?, byteCount: Int) -> LegadoPageMarker? {
        guard !body.isEmpty else { return nil }
        let head = String(body.prefix(scanLimit))
        let lower = head.lowercased()
        let isError = (statusCode ?? 0) >= 400
        let title = titleText(lower)
        let weakAllowed = isError || byteCount < smallPageBytes

        // `cf-chl`/`_cf_chl_opt` chỉ có trên trang thử thách. `challenge-platform` thì Cloudflare còn chèn vào trang
        // **thường** (script dò bot) ⇒ chỉ tính khi mã ≥ 400 hoặc tiêu đề là trang chờ. WebView luôn báo mã 200.
        if lower.contains("cf-chl") || lower.contains("cf_chl") {
            return .cloudflareChallenge
        }
        if title.contains("just a moment") || title.contains("attention required") {
            return .cloudflareChallenge
        }
        if lower.contains("challenge-platform"), isError {
            return .cloudflareChallenge
        }
        if lower.contains("just a moment"), isError || lower.contains("cloudflare") {
            return .cloudflareChallenge
        }
        let captchaWords = ["captcha", "安全验证", "人机验证"]
        if captchaWords.contains(where: { title.contains($0) }) {
            return .captcha
        }
        if weakAllowed, captchaWords.contains(where: { lower.contains($0) }) {
            return .captcha
        }
        if head.contains("区域被禁止") || head.contains("1Panel") {
            return .regionBlocked
        }
        let deniedWords = ["访问被拒绝", "access denied", "403 forbidden"]
        if deniedWords.contains(where: { title.contains($0) }) {
            return .accessDenied
        }
        if weakAllowed, deniedWords.contains(where: { lower.contains($0) }) {
            return .accessDenied
        }
        return nil
    }

    /// Chữ trong `<title>…</title>` (đã hạ chữ thường), `""` khi không có.
    private static func titleText(_ lowerHTML: String) -> String {
        guard let open = lowerHTML.range(of: "<title") else { return "" }
        guard let start = lowerHTML.range(of: ">", range: open.upperBound..<lowerHTML.endIndex) else { return "" }
        let end = lowerHTML.range(of: "</title", range: start.upperBound..<lowerHTML.endIndex)?.lowerBound
            ?? lowerHTML.endIndex
        return String(lowerHTML[start.upperBound..<end].prefix(300))
    }
}
