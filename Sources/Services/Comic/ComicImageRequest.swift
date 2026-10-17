import Foundation

/// Một yêu cầu tải ảnh comic: phần tử `chap()` (`ComicPageSource`) cộng ngữ cảnh chương và tiện ích.
///
/// Thuần dữ liệu: biết **thử ứng viên nào theo thứ tự nào** và **gửi header gì**, không tự tải.
/// `ComicImageLoader` là nơi duy nhất thực thi.
public struct ComicImageRequest: Sendable, Hashable {
    public let source: ComicPageSource
    /// URL chương đã resolve; nguồn của `Referer` mặc định (origin + "/").
    public let chapterUrl: String
    public let extensionLocalPath: String
    public let downloadUrl: String
    public let configJson: String

    public init(
        source: ComicPageSource,
        chapterUrl: String,
        extensionLocalPath: String,
        downloadUrl: String = "",
        configJson: String = "{}"
    ) {
        self.source = source
        self.chapterUrl = chapterUrl
        self.extensionLocalPath = extensionLocalPath
        self.downloadUrl = downloadUrl
        self.configJson = configJson
    }

    /// UA iPhone Safari — cùng chuỗi với `fetch` của JS (`JSExecutor.swift`, `request.setValue(... "User-Agent")`)
    /// và `UserAgent.ios()` (`JSCoreBootstrapScripts.userAgent`), để CDN thấy ảnh và HTML đến từ cùng một "trình duyệt".
    /// TODO(gộp comic/video): hai chỗ kia chưa dùng hằng này vì nằm ngoài phạm vi file của đợt này.
    public static let iPhoneSafariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// Một ứng viên nguồn byte của ảnh.
    enum Candidate: Sendable, Hashable {
        /// `http(s)` — tải qua `URLSession.shared` (dùng chung cookie với `fetch` của JS).
        case remote(URL)
        /// `file://` — ảnh đã tải offline, đọc thẳng từ đĩa.
        case file(URL)
        /// `data:` URI — giải ngay, không qua mạng.
        case inline(String)

        var isRemote: Bool {
            if case .remote = self { return true }
            return false
        }
    }

    /// Tên file script ảnh (`{link, script:"image.js"}`), chỉ khi `link` là `http(s)` — đúng
    /// extension-api.md: "Used only for http(s) links". Khi đó `link` là chuỗi **nguyên văn** truyền vào
    /// `execute(link)` (cuutruyen gói `URL + " " + JSON`), không được chuẩn hoá.
    var scriptName: String? {
        guard let script = source.script?.trimmingCharacters(in: .whitespacesAndNewlines), !script.isEmpty else {
            return nil
        }
        let link = source.link.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard link.hasPrefix("http://") || link.hasPrefix("https://") else { return nil }
        return script
    }

    /// Danh tính ảnh cho cache đĩa/RAM: `link` chính (không phải fallback nào tải được), cộng thư mục
    /// tiện ích + tên script khi ảnh do script dựng (cùng `link` qua hai script là hai ảnh khác nhau).
    var cacheKey: String {
        if let script = scriptName {
            let folder = URL(fileURLWithPath: extensionLocalPath).lastPathComponent
            return "script|\(folder)|\(script)|\(source.link)"
        }
        return source.link.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ảnh nằm sẵn trên máy (offline / `data:`) thì không cần cache đĩa.
    var isLocalOnly: Bool {
        guard scriptName == nil, let first = candidates.first else { return false }
        return !first.isRemote
    }

    /// `link` rồi lần lượt từng `fallback`, đã chuẩn hoá và bỏ trùng. Phần tử không dựng được URL bị bỏ.
    var candidates: [Candidate] {
        var result: [Candidate] = []
        for raw in [source.link] + source.fallbacks {
            guard let candidate = Self.candidate(from: raw, relativeTo: chapterUrl),
                  !result.contains(candidate) else { continue }
            result.append(candidate)
        }
        return result
    }

    /// Header cho request ảnh. Ưu tiên: `source.headers` > `source.referer` > mặc định
    /// (`Referer: <origin của chapterUrl>/` + UA iPhone Safari) — UNKNOWN U1/U2 của plan comic/video.
    var httpHeaders: [String: String] {
        var headers: [String: String] = ["User-Agent": Self.iPhoneSafariUserAgent]
        if let origin = Self.origin(of: chapterUrl) {
            headers["Referer"] = origin + "/"
        }
        if let referer = source.referer?.trimmingCharacters(in: .whitespacesAndNewlines), !referer.isEmpty {
            headers["Referer"] = referer
        }
        for (key, value) in source.headers {
            // Header HTTP không phân biệt hoa thường: `referer` của tiện ích phải đè được `Referer` mặc định.
            for existing in headers.keys where existing.caseInsensitiveCompare(key) == .orderedSame {
                headers.removeValue(forKey: existing)
            }
            headers[key] = value
        }
        return headers
    }

    // MARK: - Chuẩn hoá

    /// `//x` → `https://x`; `file://` và `data:` giữ nguyên loại; URL tương đối resolve theo URL chương.
    static func candidate(from raw: String, relativeTo baseUrl: String) -> Candidate? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()

        if lowered.hasPrefix("data:") {
            return .inline(trimmed)
        }
        if lowered.hasPrefix("file://") {
            guard let url = URL(string: trimmed), url.isFileURL else { return nil }
            return .file(url)
        }

        let absolute = trimmed.hasPrefix("//") ? "https:" + trimmed : trimmed
        if let url = URL(string: absolute), let scheme = url.scheme?.lowercased() {
            guard scheme == "http" || scheme == "https", url.host != nil else { return nil }
            return .remote(url)
        }
        // Tương đối (tiện ích quên ghép host): resolve theo URL chương.
        guard let base = URL(string: baseUrl),
              let resolved = URL(string: absolute, relativeTo: base)?.absoluteURL,
              let scheme = resolved.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return .remote(resolved)
    }

    /// `scheme://host[:port]` của một URL, `nil` khi không parse được.
    static func origin(of urlString: String) -> String? {
        guard let components = URLComponents(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else { return nil }
        let port = components.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    /// Chỉ phần host — dùng cho log (không log URL đầy đủ vì query có thể chứa token).
    static func logLabel(for candidate: Candidate) -> String {
        switch candidate {
        case .remote(let url): return url.host ?? "?"
        case .file: return "file"
        case .inline: return "data"
        }
    }
}
