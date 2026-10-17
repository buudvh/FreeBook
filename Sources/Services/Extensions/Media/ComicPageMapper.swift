import Foundation
import JavaScriptCore

/// Ánh xạ kết quả `chap.js` của tiện ích **truyện tranh** sang `[ComicPageSource]` — hàm thuần, không I/O.
///
/// `data` theo hợp đồng VBook là **mảng**; mỗi phần tử là:
/// - chuỗi URL (mangadex, truyenvn);
/// - object `{link | url, fallback | fallbacks, script, width, height, referer, headers}` (nettruyen, truyenqq,
///   cuutruyen, ext cộng đồng).
///
/// Chuẩn hoá URL (theo thứ tự): `//x` → `https://x`; đã có scheme (`http(s):`, `data:`, `file:`, `blob:`) thì giữ
/// nguyên; còn lại (tương đối) mới đi qua `JSExecutor.cleanAndResolveUrl` để ghép `host`. Không cho URL tuyệt đối
/// qua `cleanAndResolveUrl`: hàm đó giữ `https://` **cuối cùng** nên làm hỏng URL proxy kiểu `…?u=https://…`.
/// Phần tử có `script` giữ `link` **nguyên văn** (cuutruyen gói `URL + " " + JSON` trong `link`).
///
/// Dự phòng ngoài hợp đồng: chuỗi đơn (nhiều URL cách nhau xuống dòng) hoặc một object đơn cũng được nhận.
enum ComicPageMapper {
    static func map(_ value: JSValue, host: String?) -> [ComicPageSource] {
        if value.isArray {
            return JSValueReader.array(value).compactMap { page(from: $0, host: host) }
        }
        if value.isString, let text = value.toString() {
            return text
                .components(separatedBy: .newlines)
                .compactMap { (line: String) -> ComicPageSource? in
                    let link = normalizeURL(line, host: host)
                    return link.isEmpty ? nil : ComicPageSource(link: link)
                }
        }
        if JSValueReader.isPlainObject(value), let single = page(from: value, host: host) {
            return [single]
        }
        return []
    }

    /// Một phần tử mảng → ảnh; `nil` khi không có link dùng được.
    static func page(from item: JSValue, host: String?) -> ComicPageSource? {
        if item.isString {
            let link = normalizeURL(item.toString() ?? "", host: host)
            return link.isEmpty ? nil : ComicPageSource(link: link)
        }
        guard JSValueReader.isPlainObject(item) else { return nil }

        let rawLink = JSValueReader.nonEmptyString(item.forProperty("link"))
            ?? JSValueReader.nonEmptyString(item.forProperty("url"))
        guard let rawLink else { return nil }

        let script = JSValueReader.nonEmptyString(item.forProperty("script"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Có `script` ⇒ `link` là input opaque của script: giữ nguyên văn từng byte.
        let link = script == nil ? normalizeURL(rawLink, host: host) : rawLink
        guard !link.isEmpty else { return nil }

        let fallbackValue = JSValueReader.isPresent(item.forProperty("fallback"))
            ? item.forProperty("fallback")
            : item.forProperty("fallbacks")
        let fallbacks = JSValueReader.stringArray(fallbackValue)
            .map { normalizeURL($0, host: host) }
            .filter { !$0.isEmpty && $0 != link }

        let referer = JSValueReader.nonEmptyString(item.forProperty("referer"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        return ComicPageSource(
            link: link,
            fallbacks: fallbacks,
            script: script,
            width: positive(JSValueReader.int(item.forProperty("width"))),
            height: positive(JSValueReader.int(item.forProperty("height"))),
            referer: referer,
            headers: JSValueReader.stringDictionary(item.forProperty("headers"))
        )
    }

    /// `//x` → `https://x`; có scheme ⇒ giữ; tương đối ⇒ ghép `host`. Chuỗi rỗng ⇒ `""`.
    static func normalizeURL(_ raw: String, host: String?) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("//") {
            return "https:" + trimmed
        }
        if hasScheme(trimmed) {
            return trimmed
        }
        return JSExecutor.cleanAndResolveUrl(trimmed, host: host)
    }

    private static let keptSchemes = ["http://", "https://", "data:", "file:", "blob:"]

    private static func hasScheme(_ url: String) -> Bool {
        let lower = url.lowercased()
        return keptSchemes.contains { lower.hasPrefix($0) }
    }

    private static func positive(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
