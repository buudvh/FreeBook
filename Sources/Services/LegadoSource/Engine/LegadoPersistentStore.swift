import Foundation

/// Kho bền theo nguồn mà engine dùng (spec §5.7, §6.5, §6.7, §4.2, §5.8). Khoá thực luôn kèm `sourceKey`
/// (`bookSourceUrl` nguyên văn) để nguồn không đọc trộm dữ liệu của nhau.
///
/// Bản cài mặc định: `LegadoFileStateStore.shared` (file JSON dưới `applicationSupport/legado_state/`). Mọi hàm phải an
/// toàn đa luồng: nhiều phiên của các nguồn khác nhau chạy song song.
protocol LegadoPersistentStore: AnyObject {
    /// `source.getVariable()` — chuỗi người dùng sửa được (gợi ý ở `variableComment`).
    func sourceVariable(sourceKey: String) -> String
    func setSourceVariable(_ value: String, sourceKey: String)

    /// `source.put/get` (khuyến nghị U23: bền theo nguồn).
    func sourceValue(forKey key: String, sourceKey: String) -> String?
    func setSourceValue(_ value: String, forKey key: String, sourceKey: String)

    /// `cache.put/get/delete` và `putFile/getFile` (cùng kho). `ttl` tính bằng **giây**, `nil` = không hết hạn.
    /// Thiếu hoặc hết hạn ⇒ `nil` (JS thấy `null`, U23).
    func cacheValue(forKey key: String, sourceKey: String) -> String?
    func setCacheValue(_ value: String, forKey key: String, sourceKey: String, ttl: TimeInterval?)
    func removeCacheValue(forKey key: String, sourceKey: String)

    /// Kho cookie của nguồn (`LegadoCookieJar` nạp khi tạo, ghi lại khi phiên kết thúc nếu đổi).
    func cookies(sourceKey: String) -> [LegadoStoredCookie]
    func setCookies(_ cookies: [LegadoStoredCookie], sourceKey: String)

    /// Bản đã tải của `jsLib` dạng `{tên: url}` (đệm bền theo URL).
    func libraryScript(url: String) -> String?
    func setLibraryScript(_ script: String, url: String)

    /// `java.androidId()`: 16 hex ngẫu nhiên, sinh một lần, ổn định qua các lần mở app.
    func deviceIdentifier() -> String
}
