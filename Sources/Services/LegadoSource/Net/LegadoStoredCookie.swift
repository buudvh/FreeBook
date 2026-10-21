import Foundation

/// Một cookie trong kho cookie theo nguồn (`LegadoCookieJar`). Tên miền không có dấu chấm đầu, viết thường.
/// Bỏ qua `path`/`secure`: kho chỉ phục vụ request của chính nguồn, gửi theo tên miền (spec §4.2).
struct LegadoStoredCookie: Codable, Equatable {
    var domain: String
    var name: String
    var value: String
    /// Giây epoch; `nil` = cookie phiên (vẫn lưu, như tài liệu nói kho tự lưu `Set-Cookie`).
    var expires: Double?

    func isExpired(at now: Date = Date()) -> Bool {
        guard let expires else { return false }
        return expires <= now.timeIntervalSince1970
    }

    /// Cookie này có được gửi tới `host` không (trùng tên miền hoặc là tên miền con).
    func matches(host: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}
