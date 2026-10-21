import Foundation

/// Trạng thái của một lần chạy `loginCheckJs` (spec §10.7): request vừa xong, rule URL gốc, để `java.ruleUrl`,
/// `java.initUrl()`, `java.getHeaderMap()`, `java.getStrResponse()` làm việc trên đúng request đó.
struct LegadoLoginCheckContext {
    /// Rule URL như nguồn viết (có thể tương đối, có thể kèm `,{option}`) — `java.ruleUrl`.
    let ruleUrl: String
    /// URL nền đã dùng khi dựng request (`nil` ⇒ URL gốc của nguồn).
    let baseUrl: String?
    let key: String?
    let page: Int?
    /// `ruleContent.webJs` của request luồng chính (nếu có).
    let webJs: String?
    /// Request đang dựng; `initUrl()` dựng lại, `getStrResponse()` gửi lại.
    var request: LegadoHTTPRequest
}
