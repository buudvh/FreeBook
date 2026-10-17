import Foundation

/// Phân giải `VideoTrack` (kết quả `track.js`) thành `VideoPlaybackPlan` theo hợp đồng VBook:
/// - `native`: URL m3u8/mp4 tuyệt đối → `.native`; text `#EXTM3U` hoặc URI `data:` chứa HLS → `.hlsText`.
/// - `auto`: URL trang xem/embed → dò link bằng `VideoMediaSniffer` → `.native`; không ra thì **báo lỗi**
///   (đúng DOC, không có fallback nhúng trang).
/// - `webview`: URL, HTML hoặc JSON `{"data":…,"host":…}` → dò như `auto`; không ra thì `.embed`
///   (src iframe tuyệt đối nếu có, không thì nhúng nguyên HTML với base = host).
///
/// Header: header dò được (Referer/Origin/UA) rồi `track.headers` đè lên, so khoá không phân biệt hoa thường —
/// header của ext luôn thắng. `track.data` không bao giờ bị sửa; chỉ dùng bản trim để nhận dạng dạng dữ liệu.
@MainActor
public final class VideoSourceResolver {
    public enum ResolveError: LocalizedError {
        case emptyData
        case invalidURL
        case unsupportedDataURI
        case mediaNotFound
        case invalidWebviewData

        public var errorDescription: String? {
            switch self {
            case .emptyData:
                return "Tập phim không có dữ liệu nguồn phát."
            case .invalidURL:
                return "Link phát không hợp lệ (cần URL http(s) tuyệt đối)."
            case .unsupportedDataURI:
                return "Chỉ hỗ trợ URI data: chứa playlist HLS."
            case .mediaNotFound:
                return "Không tìm thấy link video trong trang xem. Hãy thử server khác."
            case .invalidWebviewData:
                return "Dữ liệu nhúng trang của tiện ích không hợp lệ."
            }
        }
    }

    private var sniffer: VideoMediaSniffer?
    /// Tăng mỗi lần `resolve`/`cancel`; lượt cũ thấy lệch thì ném `CancellationError` (lượt mới nhất thắng).
    private var generation = 0

    private static let iframeSourceRegex = try? NSRegularExpression(
        pattern: #"<iframe\b[^>]*?\bsrc\s*=\s*["']([^"']+)["']"#,
        options: [.caseInsensitive]
    )

    public init() {}

    /// `extensionLocalPath` dùng để lấy `metadata.source` trong `plugin.json` làm base khi track không có `host`.
    public func resolve(_ track: VideoTrack, extensionLocalPath: String) async throws -> VideoPlaybackPlan {
        cancel()
        let current = generation
        let baseURL = Self.baseURL(host: track.host, extensionLocalPath: extensionLocalPath)
        do {
            let plan: VideoPlaybackPlan
            switch track.kind {
            case .native:
                plan = try Self.nativePlan(track, baseURL: baseURL)
            case .auto:
                plan = try await autoPlan(track, baseURL: baseURL, generation: current)
            case .webview:
                plan = try await webviewPlan(track, baseURL: baseURL, generation: current)
            }
            try ensureCurrent(current)
            AppLogger.shared.log("🎬 [VideoSourceResolver] \(track.kind.rawValue) → \(Self.describe(plan))")
            return plan
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLogger.shared.log("❌ [VideoSourceResolver] Phân giải track \(track.kind.rawValue) thất bại: \(error.localizedDescription)")
            throw error
        }
    }

    public func cancel() {
        generation += 1
        sniffer?.cancel()
        sniffer = nil
    }

    // MARK: - Theo loại track

    private static func nativePlan(_ track: VideoTrack, baseURL: URL?) throws -> VideoPlaybackPlan {
        let probe = VideoDataURI.stripBOM(track.data).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !probe.isEmpty else { throw ResolveError.emptyData }
        if probe.hasPrefix("#EXTM3U") {
            return .hlsText(playlist: track.data, baseURL: baseURL, headers: track.headers)
        }
        if VideoDataURI.isDataURI(probe) {
            // DOC: chỉ URI data: chứa HLS; DASH/MP4 dạng data: là lỗi.
            guard let decoded = VideoDataURI.decode(probe), decoded.isHLSPlaylist else {
                throw ResolveError.unsupportedDataURI
            }
            return .hlsText(playlist: decoded.text, baseURL: baseURL, headers: track.headers)
        }
        guard let url = webURL(probe, relativeTo: baseURL) else { throw ResolveError.invalidURL }
        return .native(url: url, headers: track.headers)
    }

    private func autoPlan(_ track: VideoTrack, baseURL: URL?, generation: Int) async throws -> VideoPlaybackPlan {
        let probe = track.data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !probe.isEmpty else { throw ResolveError.emptyData }
        guard let pageURL = Self.webURL(probe, relativeTo: baseURL) else { throw ResolveError.invalidURL }
        if VideoMediaSniffer.isDirectMediaURL(pageURL) {
            return .native(url: pageURL, headers: track.headers)
        }
        guard let found = try await sniff(.url(pageURL), generation: generation) else {
            throw ResolveError.mediaNotFound
        }
        return .native(url: found.url, headers: Self.merge(found.headers, overriddenBy: track.headers))
    }

    private func webviewPlan(_ track: VideoTrack, baseURL: URL?, generation: Int) async throws -> VideoPlaybackPlan {
        var content = track.data
        var base = baseURL
        if let wrapped = Self.unwrapJSON(content) {
            content = wrapped.data
            if let host = wrapped.host,
               let hostURL = Self.webURL(host.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: nil) {
                base = hostURL
            }
        }
        let probe = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !probe.isEmpty else { throw ResolveError.emptyData }

        if Self.looksLikeHTML(probe) {
            if let found = try await sniff(.html(content, baseURL: base), generation: generation) {
                return .native(url: found.url, headers: Self.merge(found.headers, overriddenBy: track.headers))
            }
            AppLogger.shared.log("🎬 [VideoSourceResolver] webview: không bắt được link, chuyển sang nhúng trang")
            if let iframe = Self.absoluteIframeSource(in: content) {
                return .embed(url: iframe, html: nil, baseURL: base)
            }
            return .embed(url: nil, html: content, baseURL: base)
        }

        // `<!DOCTYPE html>` trần (không `<body`) cũng rơi xuống đây và bị từ chối như DOC.
        guard let pageURL = Self.webURL(probe, relativeTo: base) else { throw ResolveError.invalidWebviewData }
        if VideoMediaSniffer.isDirectMediaURL(pageURL) {
            return .native(url: pageURL, headers: track.headers)
        }
        if let found = try await sniff(.url(pageURL), generation: generation) {
            return .native(url: found.url, headers: Self.merge(found.headers, overriddenBy: track.headers))
        }
        AppLogger.shared.log("🎬 [VideoSourceResolver] webview: không bắt được link, chuyển sang nhúng trang")
        return .embed(url: pageURL, html: nil, baseURL: base)
    }

    private func sniff(_ page: VideoMediaSniffer.Page, generation: Int) async throws -> VideoMediaSniffer.Result? {
        try ensureCurrent(generation)
        let sniffer = VideoMediaSniffer()
        self.sniffer = sniffer
        defer {
            if self.sniffer === sniffer { self.sniffer = nil }
        }
        let result = try await sniffer.sniff(page)
        try ensureCurrent(generation)
        return result
    }

    private func ensureCurrent(_ value: Int) throws {
        if value != generation || Task.isCancelled { throw CancellationError() }
    }

    // MARK: - Tiện ích

    /// `host` của track; thiếu hoặc hỏng thì lấy `metadata.source` trong `plugin.json` của ext.
    private static func baseURL(host: String?, extensionLocalPath: String) -> URL? {
        if let host, let url = webURL(host.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: nil) {
            return url
        }
        guard !extensionLocalPath.isEmpty else { return nil }
        let manifest = URL(fileURLWithPath: extensionLocalPath).appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = json["metadata"] as? [String: Any],
              let source = metadata["source"] as? String else { return nil }
        return webURL(source.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: nil)
    }

    /// URL http(s) tuyệt đối; `//host/…` thêm `https:`; tương đối thì resolve theo `base` (nới hơn DOC một chút).
    static func webURL(_ raw: String, relativeTo base: URL?) -> URL? {
        guard !raw.isEmpty else { return nil }
        let candidate = raw.hasPrefix("//") ? "https:" + raw : raw
        if let url = URL(string: candidate), isWebURL(url), url.host != nil {
            return url
        }
        guard let base, let url = URL(string: candidate, relativeTo: base)?.absoluteURL, isWebURL(url) else {
            return nil
        }
        return url
    }

    private static func isWebURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    /// DOC: HTML khi mở đầu bằng `<iframe`/`<html`, hoặc chứa `<body`/`<video` (không phân biệt hoa thường).
    private static func looksLikeHTML(_ probe: String) -> Bool {
        let lower = probe.lowercased()
        return lower.hasPrefix("<iframe") || lower.hasPrefix("<html") || lower.contains("<body") || lower.contains("<video")
    }

    private static func unwrapJSON(_ raw: String) -> (data: String, host: String?)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = object["data"] as? String else { return nil }
        return (inner, object["host"] as? String)
    }

    private static func absoluteIframeSource(in html: String) -> URL? {
        guard let regex = iframeSourceRegex else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let sourceRange = Range(match.range(at: 1), in: html) else { return nil }
        let source = String(html[sourceRange])
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return webURL(source, relativeTo: nil)
    }

    /// `overrides` (header của ext) thắng; khoá trùng khác hoa thường thì bỏ khoá của `base`.
    static func merge(_ base: [String: String], overriddenBy overrides: [String: String]) -> [String: String] {
        let overrideKeys = Set(overrides.keys.map { $0.lowercased() })
        var merged = base.filter { !overrideKeys.contains($0.key.lowercased()) }
        for (key, value) in overrides {
            merged[key] = value
        }
        return merged
    }

    /// Không log URL đầy đủ (query thường có token).
    private static func describe(_ plan: VideoPlaybackPlan) -> String {
        switch plan {
        case .native(let url, _):
            return "native \(VideoMediaSniffer.redacted(url))"
        case .hlsText(let playlist, _, _):
            return "playlist text \(playlist.utf8.count) byte"
        case .embed(let url, _, _):
            return url.map { "nhúng \(VideoMediaSniffer.redacted($0))" } ?? "nhúng HTML"
        }
    }
}
