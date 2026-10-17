import Foundation

/// Phân giải `VideoTrack` (kết quả `track.js`) thành `VideoPlaybackPlan` theo hợp đồng extension:
/// - `native`: URL m3u8/mp4 tuyệt đối → `.native`; text `#EXTM3U` hoặc URI `data:` chứa HLS → `.hlsText`.
/// - `auto`: URL trang xem/embed → dò link bằng `VideoMediaSniffer` → `.native`; không ra thì **báo lỗi**
///   (đúng DOC, không có fallback nhúng trang).
/// - `webview`: URL, HTML hoặc JSON `{"data":…,"host":…}` → dò như `auto`; không ra thì `.embed`
///   (src iframe tuyệt đối nếu có, không thì nhúng nguyên HTML với base = host).
/// - Link dò được (`auto`/`webview`) kèm phương án dự phòng cho ca **mất tiếng** (`VideoSourceResolution`): các m3u8
///   khác đã gom rồi nhúng trang. Với `auto` đây là ngoại lệ có chủ đích so với DOC — chỉ dùng khi item phát ra hình
///   mà không có tiếng, không dùng khi không dò được link.
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
        try await resolveSource(track, extensionLocalPath: extensionLocalPath).current.plan
    }

    /// Như `resolve`, kèm nguồn gốc link và phương án dự phòng khi item mất tiếng.
    func resolveSource(_ track: VideoTrack, extensionLocalPath: String) async throws -> VideoSourceResolution {
        cancel()
        let current = generation
        let baseURL = Self.baseURL(host: track.host, extensionLocalPath: extensionLocalPath)
        do {
            let resolution: VideoSourceResolution
            switch track.kind {
            case .native:
                resolution = try VideoSourceResolution(direct: Self.nativePlan(track, baseURL: baseURL))
            case .auto:
                resolution = try await autoPlan(track, baseURL: baseURL, generation: current)
            case .webview:
                resolution = try await webviewPlan(track, baseURL: baseURL, generation: current)
            }
            try ensureCurrent(current)
            let spare = resolution.fallbacks.isEmpty
                ? ""
                : " (dự phòng khi mất tiếng: \(resolution.fallbacks.count) phương án)"
            AppLogger.shared.log("🎬 [VideoSourceResolver] \(track.kind.rawValue) → \(Self.describe(resolution.current.plan))\(spare)")
            return resolution
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
        guard let url = webURL(urlText(probe), relativeTo: baseURL) else { throw ResolveError.invalidURL }
        return .native(url: url, headers: track.headers)
    }

    private func autoPlan(_ track: VideoTrack, baseURL: URL?, generation: Int) async throws -> VideoSourceResolution {
        let probe = track.data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !probe.isEmpty else { throw ResolveError.emptyData }
        guard let pageURL = Self.webURL(Self.urlText(probe), relativeTo: baseURL) else { throw ResolveError.invalidURL }
        if VideoMediaSniffer.isDirectMediaURL(pageURL) {
            return VideoSourceResolution(direct: .native(url: pageURL, headers: track.headers))
        }
        guard let found = try await sniff(.url(pageURL), generation: generation) else {
            throw ResolveError.mediaNotFound
        }
        return Self.sniffedResolution(found, track: track, embed: .embed(url: pageURL, html: nil, baseURL: baseURL))
    }

    private func webviewPlan(_ track: VideoTrack, baseURL: URL?, generation: Int) async throws -> VideoSourceResolution {
        var content = track.data
        var base = baseURL
        if let wrapped = Self.unwrapJSON(content) {
            content = wrapped.data
            if let host = wrapped.host,
               let hostURL = Self.webURL(Self.urlText(host), relativeTo: nil) {
                base = hostURL
            }
        }
        let probe = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !probe.isEmpty else { throw ResolveError.emptyData }

        if Self.looksLikeHTML(probe) {
            let embed = Self.htmlEmbedPlan(content, baseURL: base)
            if let found = try await sniff(.html(content, baseURL: base), generation: generation) {
                return Self.sniffedResolution(found, track: track, embed: embed)
            }
            AppLogger.shared.log("🎬 [VideoSourceResolver] webview: không bắt được link, chuyển sang nhúng trang")
            return VideoSourceResolution(direct: embed)
        }

        // `<!DOCTYPE html>` trần (không `<body`) cũng rơi xuống đây và bị từ chối như DOC.
        guard let pageURL = Self.webURL(Self.urlText(probe), relativeTo: base) else { throw ResolveError.invalidWebviewData }
        if VideoMediaSniffer.isDirectMediaURL(pageURL) {
            return VideoSourceResolution(direct: .native(url: pageURL, headers: track.headers))
        }
        let embed = VideoPlaybackPlan.embed(url: pageURL, html: nil, baseURL: base)
        if let found = try await sniff(.url(pageURL), generation: generation) {
            return Self.sniffedResolution(found, track: track, embed: embed)
        }
        AppLogger.shared.log("🎬 [VideoSourceResolver] webview: không bắt được link, chuyển sang nhúng trang")
        return VideoSourceResolution(direct: embed)
    }

    /// Link dò được ⇒ phương án chính + tối đa `maxAlternateCandidates` m3u8 khác (đã xếp hạng) + nhúng trang cuối
    /// cùng. Header của ext đè header dò được ở mọi phương án native.
    private static func sniffedResolution(
        _ found: VideoMediaSniffer.Result,
        track: VideoTrack,
        embed: VideoPlaybackPlan
    ) -> VideoSourceResolution {
        func attempt(_ result: VideoMediaSniffer.Result) -> VideoSourceResolution.Attempt {
            let headers = merge(result.headers, overriddenBy: track.headers)
            let plan = VideoPlaybackPlan.native(url: result.url, headers: headers)
            return VideoSourceResolution.Attempt(plan: plan, origin: .sniffed, note: result.label)
        }
        let alternates = found.alternatives.prefix(VideoSourceResolution.maxAlternateCandidates).map { attempt($0) }
        let last = VideoSourceResolution.Attempt(plan: embed, origin: .embed, note: nil)
        return VideoSourceResolution(
            current: attempt(found),
            fallbacks: alternates + [last],
            playlistSummary: found.playlistSummary
        )
    }

    /// HTML của `webview`: src iframe tuyệt đối nếu có, không thì nhúng nguyên HTML với base = host.
    private static func htmlEmbedPlan(_ html: String, baseURL: URL?) -> VideoPlaybackPlan {
        if let iframe = absoluteIframeSource(in: html) {
            return .embed(url: iframe, html: nil, baseURL: baseURL)
        }
        return .embed(url: nil, html: html, baseURL: baseURL)
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

    /// `host` của track; thiếu hoặc hỏng thì lấy `source` của tiện ích (bản cài; bản nháp debug ⇒ `plugin.json`).
    private static func baseURL(host: String?, extensionLocalPath: String) -> URL? {
        if let host, let url = webURL(urlText(host), relativeTo: nil) {
            return url
        }
        guard let source = ExtensionHostResolver.sourceUrl(localPath: extensionLocalPath) else { return nil }
        return webURL(source, relativeTo: nil)
    }

    /// Chuỗi `data`/`host` của track **trước khi hiểu là URL**: giải escape kiểu JSON còn sót (`\t`, `\n`, `\r`,
    /// `\/`, `\"`, `\\`, `\uXXXX`) rồi bỏ khoảng trắng/tab/xuống dòng hai đầu. Ca thật: `track.js` của HHHTQ lấy
    /// `url` trong `player_aaaa` bằng regex và chỉ đổi `\/`, nên trả `"\thttps://…"` (gạch ngược + `t`) — không
    /// parse được thành URL. Chỉ dùng ở bước nhận dạng URL: HLS text/HTML không đi qua đây, `track.data` gửi cho
    /// script vẫn nguyên văn.
    static func urlText(_ raw: String) -> String {
        let trimmed = VideoDataURI.stripBOM(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("\\") else { return trimmed }
        return unescapeJSON(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Giải escape trong **một lượt** (`\\t` ⇒ `\t` dạng chữ, không thành tab). Escape lạ/hỏng giữ nguyên văn.
    private static func unescapeJSON(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            guard scalar == "\\", index + 1 < scalars.count else {
                output.append(scalar)
                index += 1
                continue
            }
            let next = scalars[index + 1]
            switch next {
            case "t": output.append("\t"); index += 2
            case "n": output.append("\n"); index += 2
            case "r": output.append("\r"); index += 2
            case "/", "\"", "\\": output.append(next); index += 2
            case "u":
                if let decoded = hexScalar(scalars, from: index + 2) {
                    output.append(decoded)
                    index += 6
                } else {
                    output.append(scalar)
                    index += 1
                }
            default:
                output.append(scalar)
                index += 1
            }
        }
        return String(output)
    }

    /// 4 chữ số hex bắt đầu từ `start` ⇒ scalar; thiếu ký tự, sai hex hoặc surrogate ⇒ `nil`.
    private static func hexScalar(_ scalars: [Unicode.Scalar], from start: Int) -> Unicode.Scalar? {
        guard start + 4 <= scalars.count else { return nil }
        var hex = ""
        for scalar in scalars[start..<(start + 4)] {
            hex.unicodeScalars.append(scalar)
        }
        guard let value = UInt32(hex, radix: 16) else { return nil }
        return Unicode.Scalar(value)
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
