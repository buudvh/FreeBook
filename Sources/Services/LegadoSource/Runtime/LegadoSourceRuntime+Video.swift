import Foundation

/// Video (spec §9): tập = chương của mục lục; mỗi tập một "server" (§9.2); nguồn phát giải lại mỗi lần phát (§9.3).
extension LegadoSourceRuntime {
    /// Đuôi đường dẫn coi là tệp media (spec §9.3 bước 2, không phân biệt hoa thường, bỏ query/fragment).
    static let mediaExtensions = [".m3u8", ".mp4", ".flv", ".m4v", ".mov", ".ts"]
    /// Giá trị `type` của khối option khai "đây là media" (§9.3 bước 5).
    static let mediaOptionTypes: Set<String> = ["m3u8", "mp4", "flv", "m4v", "mov", "ts", "hls", "video"]

    /// Một server duy nhất mang URL tập + ngữ cảnh — không mạng.
    static func videoServers(_ target: Target, chapterUrl: String, context: SourceRuntimeContext?) -> [VideoServer] {
        let payload = LegadoVideoServerPayload(chapterUrl: chapterUrl, context: context)
        return [VideoServer(title: "Nguồn phát", data: payload.encoded)]
    }

    /// Giải nguồn phát của một tập (spec §9.3) thành `VideoTrack`: `.native` khi URL là tệp media (hoặc option khai
    /// `type` media), ngược lại `.webview` (trang nhúng/giải mã — `VideoSourceResolver` dò link rồi phát, không ra thì
    /// nhúng trang). Không cache, không tải trước.
    static func videoTrack(_ target: Target, payload: LegadoVideoServerPayload, log: LegadoRunLog? = nil) async throws -> VideoTrack {
        let chapterUrl = payload.chapterUrl
        return try await runChapterSession(target, chapterUrl: chapterUrl, context: payload.context, log: log) { session, _ in
            try Self.resolvePlayback(session: session, target: target, chapterUrl: chapterUrl)
        }
    }

    /// Thân phiên video (spec §9.3 bước 1–5).
    static func resolvePlayback(session: LegadoEngineSession, target: Target, chapterUrl: String) throws -> VideoTrack {
        let rule = target.source.ruleContent
        let chapterPlain = LegadoURLResolver.splitOption(chapterUrl).url
        // §9.6: `java.startBrowser(url, title)` trong `content` video không mở trình duyệt mà thành ứng viên phát.
        session.capturesBrowserAsPlaybackCandidate = true
        let raw: String
        let pageURL: String
        if nonEmpty(rule.content) == nil {
            // §9.3 bước 1: `content` rỗng ⇒ phát thẳng URL tập.
            raw = chapterUrl
            pageURL = chapterPlain
        } else if isMediaPath(chapterPlain) {
            // §9.3 bước 2 (U33): URL tập là tệp media ⇒ không tải thân, chạy `content` với `result`/`src` rỗng.
            raw = try session.analyzer(node: .string(""), baseUrl: chapterUrl, src: "").string(rule.content)
            pageURL = chapterPlain
        } else {
            // §9.3 bước 3: tải như truyện chữ; `sourceRegex` chỉ có tác dụng khi request đi WebView (§9.4, U34).
            let response = try session.fetch(chapterUrl, webJs: nonEmpty(rule.webJs), sourceRegex: nonEmpty(rule.sourceRegex))
            raw = try session.analyzer(response: response).string(rule.content)
            pageURL = response.finalURL
        }
        let candidates = session.playbackCandidates.map { $0.url }
        guard let play = playbackURL(from: raw, pageURL: pageURL, browserCandidates: candidates) else {
            throw LegadoRuntimeError.noPlayableSource
        }
        let rawRule = play.option.map { play.url + "," + $0 } ?? play.url
        let request = try session.buildRequest(rawRule, baseUrl: pageURL)
        var headers = headerDictionary(request.headers)
        if let cookie = LegadoHTTPRequest.mergeCookies(jar: session.cookieJar.cookieHeader(forURL: request.url),
                                                       manual: request.header("Cookie")), !cookie.isEmpty {
            setHeader("Cookie", cookie, in: &headers)
        }
        let declaredType = play.option.flatMap { LegadoURLOption.parse($0)?.type }?.lowercased() ?? ""
        let isNative = isMediaPath(request.url) || mediaOptionTypes.contains(declaredType)
        if !isNative, headers.contains(where: { $0.value == LegadoHTTPClient.defaultUserAgent }) {
            // Trang nhúng: trình dò dùng UA của WebView; UA mặc định của engine (nguồn không tự khai) đè lên header dò được
            // sẽ lệch với UA đã mở trang — bỏ, chỉ giữ UA do nguồn/option khai.
            headers = headers.filter { $0.value != LegadoHTTPClient.defaultUserAgent }
        }
        return VideoTrack(kind: isNative ? .native : .webview, data: request.url, host: origin(of: pageURL),
                          headers: headers)
    }

    /// Diễn giải chuỗi `R` của `content` (spec §9.3 bước 4): một URL (bỏ khối option cuối) ⇒ URL đó (tương đối ⇒ ghép
    /// URL trang); văn bản lẫn URL ⇒ URL **cuối** có đuôi media, không có thì URL `http(s)` cuối; vẫn không có ⇒ ứng viên
    /// `java.startBrowser` cuối. `nil` ⇒ không có nguồn phát.
    static func playbackURL(from raw: String, pageURL: String, browserCandidates: [String]) -> (url: String, option: String?)? {
        let text = trimmed(raw)
        let split = LegadoURLResolver.splitOption(text)
        let single = trimmed(split.url)
        if !single.isEmpty, !single.contains(where: { $0.isWhitespace }), !single.contains("<") {
            if LegadoURLResolver.hasHTTPScheme(single) { return (single, split.option) }
            let absolute = LegadoURLResolver.absolute(single, base: pageURL)
            if LegadoURLResolver.hasHTTPScheme(absolute), single.hasPrefix("/") || single.hasPrefix(".") {
                return (absolute, split.option)
            }
        }
        let found = urls(in: text)
        if let media = found.last(where: { isMediaPath($0) }) { return (media, nil) }
        if let last = found.last { return (last, nil) }
        if let candidate = browserCandidates.last(where: { !trimmed($0).isEmpty }) {
            let absolute = LegadoURLResolver.absolute(trimmed(candidate), base: pageURL)
            if LegadoURLResolver.hasHTTPScheme(absolute) {
                let parts = LegadoURLResolver.splitOption(absolute)
                return (parts.url, parts.option)
            }
        }
        return nil
    }

    /// Mọi URL `http(s)://` trong văn bản, **kể cả URL lồng** (`…/?url=https://…m3u8`), theo thứ tự xuất hiện; mỗi URL kéo
    /// tới khoảng trắng, nháy, `<`, `>` hoặc dấu câu toàn góc; đã giải thực thể HTML.
    static func urls(in text: String) -> [String] {
        let stops: Set<Character> = ["\"", "'", "<", ">", "，", "。", "）", "】", "」", "、"]
        let characters = Array(text)
        var output: [String] = []
        var index = 0
        while index < characters.count {
            let rest = characters.count - index
            let isHTTP = rest >= 7 && String(characters[index..<(index + 7)]).lowercased() == "http://"
            let isHTTPS = rest >= 8 && String(characters[index..<(index + 8)]).lowercased() == "https://"
            guard isHTTP || isHTTPS else {
                index += 1
                continue
            }
            var end = index
            while end < characters.count, !characters[end].isWhitespace, !stops.contains(characters[end]) { end += 1 }
            let candidate = LegadoHTMLText.decodeEntities(String(characters[index..<end]))
            output.append(candidate)
            index += isHTTPS ? 8 : 7
        }
        return output
    }

    /// Đường dẫn (bỏ khối option, fragment, query) kết thúc bằng đuôi media (§9.3 bước 2).
    static func isMediaPath(_ url: String) -> Bool {
        var path = LegadoURLResolver.splitOption(url).url.lowercased()
        if let hash = path.firstIndex(of: "#") { path = String(path[..<hash]) }
        if let question = path.firstIndex(of: "?") { path = String(path[..<question]) }
        return mediaExtensions.contains { path.hasSuffix($0) }
    }
}
