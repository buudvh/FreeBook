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

    /// Bộ khớp **cả chuỗi** đúng hợp đồng tiện ích (`String.matches` của Kotlin): `regexp` phải phủ hết link, thử link
    /// nguyên văn rồi link bỏ `http(s)://` và dấu `/` cuối. Dùng cho việc tự gắn lại nguồn của truyện mất nguồn
    /// (`MissingSourceRebindCoordinator`), nơi khớp nhầm là đổi sai nguồn; `matches(for:in:)` (khớp một phần) giữ
    /// nguyên cho nút Nhập và dịch trang. Biểu thức dựng **một lần** cho cả danh sách rồi thử nhiều link.
    struct WholeMatcher {
        private let entries: [(ext: Extension, regexp: String, regex: NSRegularExpression)]

        init(extensions: [Extension]) {
            entries = extensions.compactMap { (ext: Extension) -> (ext: Extension, regexp: String, regex: NSRegularExpression)? in
                guard let pattern = ExtensionUrlMatcher.regexp(localPath: ext.localPath), !pattern.isEmpty,
                      let regex = try? NSRegularExpression(pattern: "\\A(?:\(pattern))\\z", options: [.caseInsensitive]) else {
                    return nil
                }
                return (ext: ext, regexp: pattern, regex: regex)
            }
        }

        var isEmpty: Bool { entries.isEmpty }

        /// Tiện ích khớp `urlString`, giữ thứ tự danh sách đầu vào. Chỉ nhận link http(s).
        func matches(for urlString: String) -> [Match] {
            let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("http") else { return [] }
            var bare = trimmed.replacingOccurrences(of: "^https?://", with: "", options: [.regularExpression, .caseInsensitive])
            while bare.hasSuffix("/") { bare.removeLast() }
            let variants = bare == trimmed ? [trimmed] : [trimmed, bare]
            return entries.compactMap { entry in
                let hit = variants.contains { text in
                    entry.regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) != nil
                }
                return hit ? Match(ext: entry.ext, regexp: entry.regexp) : nil
            }
        }
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

        guard let json = ExtensionPackageReader.manifest(localPath: localPath),
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
