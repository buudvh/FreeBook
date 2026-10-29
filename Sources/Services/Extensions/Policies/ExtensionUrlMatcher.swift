import Foundation

/// Dò tiện ích nhận một link trang truyện theo `metadata.regexp` trong `plugin.json` — dùng chung cho nút nhập truyện
/// của trình duyệt (`BypassWebView`) và bước "Từ URL" của sheet Nhập truyện ở Kệ.
///
/// - Ứng viên (`candidates`) = tiện ích đã cài, **bỏ nguồn Legado**: không phải lối nhập (hàng nghìn nguồn) và
///   `plugin.json` của chúng không có `regexp`, dò chỉ tốn một lần đọc file mỗi nguồn.
/// - `regexp` được nhớ theo `localPath` (đọc `plugin.json` một lần mỗi tiện ích). Màn Cấu hình tiện ích sửa `regexp`
///   thì gọi `invalidateRegexpCache(localPath:)` — không xoá thì bản mới chỉ có hiệu lực sau khi mở lại app.
/// - Có lock: gọi được từ thread bất kỳ.
enum ExtensionUrlMatcher {
    struct Match: Identifiable {
        let ext: Extension
        let regexp: String

        var id: String { ext.packageId }
    }

    private static let lock = NSLock()
    private static var regexpCache: [String: String] = [:]

    /// Tiện ích đem ra dò: bản cài hiện tại trừ nguồn Legado.
    static func candidates(from installed: [Extension]) -> [Extension] {
        LegadoSourcePolicy.excludingLegado(installed)
    }

    /// Các tiện ích có `regexp` khớp `urlString` (không phân biệt hoa thường), giữ thứ tự `extensions`. Chỉ nhận link
    /// http(s).
    static func matches(for urlString: String, in extensions: [Extension]) -> [Match] {
        guard !urlString.isEmpty, urlString.lowercased().hasPrefix("http") else { return [] }

        let range = NSRange(location: 0, length: urlString.utf16.count)
        var matches: [Match] = []
        for ext in extensions {
            guard let pattern = regexp(localPath: ext.localPath), !pattern.isEmpty,
                  let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            if regex.firstMatch(in: urlString, options: [], range: range) != nil {
                matches.append(Match(ext: ext, regexp: pattern))
            }
        }
        return matches
    }

    /// Xoá cache regexp của **một** tiện ích (chỉ một khoá, để tiện ích khác không phải đọc lại `plugin.json`).
    static func invalidateRegexpCache(localPath: String) {
        guard !localPath.isEmpty else { return }
        lock.lock()
        regexpCache.removeValue(forKey: localPath)
        lock.unlock()
    }

    /// `metadata.regexp` của tiện ích ở `localPath`; không có file / không có trường ⇒ `nil` (không nhớ kết quả rỗng).
    static func regexp(localPath: String) -> String? {
        guard !localPath.isEmpty else { return nil }
        lock.lock()
        let cached = regexpCache[localPath]
        lock.unlock()
        if let cached { return cached }

        let pluginJsonUrl = URL(fileURLWithPath: localPath).appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: pluginJsonUrl.path),
              let data = try? Data(contentsOf: pluginJsonUrl),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = json["metadata"] as? [String: Any],
              let regexp = metadata["regexp"] as? String else {
            return nil
        }
        lock.lock()
        regexpCache[localPath] = regexp
        lock.unlock()
        return regexp
    }
}
