import Foundation

/// Ghép luồng hình + luồng tiếng riêng (`audios` của track `native`) thành một playlist HLS gốc (master) tổng hợp.
///
/// Ca thật: Dailymotion trả `data` = playlist con (media) của một chất lượng — **chỉ có hình** — còn tiếng nằm ở
/// `audios`. Phát thẳng playlist con đó ra hình mà mất tiếng. Playlist gốc tổng hợp khai mỗi luồng tiếng là một rendition
/// `#EXT-X-MEDIA:TYPE=AUDIO` cùng nhóm và một biến thể `#EXT-X-STREAM-INF` trỏ tới luồng hình; phát qua nhánh `.hlsText`
/// (`HLSPlaylistResourceLoader`).
///
/// - `data` là playlist gốc (có `#EXT-X-STREAM-INF`) ⇒ không ghép, bỏ qua `audios` (master tự khai tiếng).
/// - `data` là URL m3u8 (đuôi `.m3u8`/`.m3u` hoặc `mimeType` chứa `mpegurl`): tải nhanh bằng
///   `VideoHLSPlaylistProbe.shape(ofRemote:)` (cùng header, hạn chót ngắn). Playlist con hoặc tải lỗi ⇒ ghép; tải được
///   mà không phải m3u8 ⇒ không ghép. URL không giống m3u8 (mp4…) ⇒ không tải, không ghép (giữ hành vi cũ).
/// - `data` là text `#EXTM3U` / URI `data:` chứa playlist con ⇒ playlist con được phục vụ kèm qua `subPlaylists`.
/// - Chỉ nhận luồng tiếng là URL http(s) có dấu hiệu HLS (`type` chứa `mpegurl`/`m3u`, hoặc đuôi `.m3u8`/`.m3u`); URL
///   tương đối resolve theo `host` của track (thiếu thì theo URL luồng hình). AVFoundation chỉ có một bộ header cho cả
///   asset ⇒ header riêng của luồng tiếng chỉ bổ sung khoá mà `track.headers` không có.
///
/// `@MainActor` vì dùng lại các hàm nhận dạng URL của `VideoSourceResolver`; phần tải mạng chạy ngoài main.
@MainActor
enum VideoAudioRenditionComposer {
    struct Composition: Sendable {
        /// `.hlsText` phát playlist gốc tổng hợp.
        let plan: VideoPlaybackPlan
        let audioCount: Int
        /// Cho log: loại luồng hình + host/tên file của từng luồng — không có query/token.
        let summary: String
    }

    enum Outcome: Sendable {
        case composed(Composition)
        /// Không ghép (lý do cho log, không chứa URL) ⇒ phát như cũ, bỏ qua `audios`.
        case skipped(String)
    }

    private struct Rendition {
        let name: String
        let language: String?
        let uri: String
    }

    private enum VideoSource {
        case remote(URL)
        case text(String)
    }

    static let audioGroupId = "aud"
    /// `BANDWIDTH` bắt buộc trong `#EXT-X-STREAM-INF`; chỉ có một biến thể nên giá trị ước lượng không ảnh hưởng chọn luồng.
    static let estimatedBandwidth = 2_000_000
    private static let masterReason = "data là playlist gốc (master) — tự khai luồng tiếng"
    /// Thẻ ngôn ngữ BCP-47 đơn giản (`vi`, `en-US`, `zh-Hans`); giá trị khác thì bỏ thuộc tính `LANGUAGE`.
    private static let languageRegex = try? NSRegularExpression(pattern: "^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$")

    /// `nil` khi track không phải `native` hoặc không có `audios` (không có gì để ghép).
    static func compose(_ track: VideoTrack, baseURL: URL?) async -> Outcome? {
        guard track.kind == .native, !track.audios.isEmpty else { return nil }
        let headers = mergedHeaders(track)
        let probe = VideoDataURI.stripBOM(track.data).trimmingCharacters(in: .whitespacesAndNewlines)

        let source: VideoSource
        let videoLabel: String
        if probe.hasPrefix("#EXTM3U") || VideoDataURI.isDataURI(probe) {
            let text: String
            if probe.hasPrefix("#EXTM3U") {
                text = track.data
            } else if let decoded = VideoDataURI.decode(probe), decoded.isHLSPlaylist {
                text = decoded.text
            } else {
                return .skipped("URI data: không chứa playlist HLS")
            }
            switch VideoHLSPlaylistProbe.shape(ofPlaylist: text) {
            case .master:
                return .skipped(masterReason)
            case .notPlaylist, .unavailable:
                return .skipped("playlist text không mở đầu bằng #EXTM3U")
            case .media:
                source = .text(text)
                videoLabel = "playlist con dạng text"
            }
        } else {
            guard let url = VideoSourceResolver.webURL(VideoSourceResolver.urlText(probe), relativeTo: baseURL) else {
                return .skipped("data không phải URL http(s)")
            }
            guard hasHLSHint(url: url, type: track.mimeType) else {
                return .skipped("luồng hình không phải m3u8")
            }
            switch await VideoHLSPlaylistProbe.shape(ofRemote: url, headers: headers) {
            case .master:
                return .skipped(masterReason)
            case .notPlaylist:
                return .skipped("data tải về không phải playlist m3u8")
            case .media:
                videoLabel = "playlist con"
            case .unavailable:
                videoLabel = "chưa tải được để phân loại"
            }
            source = .remote(url)
        }

        var subPlaylists: [String: String] = [:]
        let videoURI: String
        let videoDescription: String
        let audioBase: URL?
        switch source {
        case .remote(let url):
            videoURI = url.absoluteString
            videoDescription = VideoSourceResolution.redact(url)
            audioBase = baseURL ?? url
        case .text(let text):
            videoURI = HLSPlaylistResourceLoader.subPlaylistURI()
            subPlaylists[videoURI] = text
            videoDescription = "\(text.utf8.count) byte"
            audioBase = baseURL
        }
        guard isSafeURI(videoURI) else { return .skipped("URL luồng hình có ký tự không hợp lệ trong playlist") }

        let accepted = renditions(of: track.audios, relativeTo: audioBase, excluding: videoURI)
        guard !accepted.isEmpty else {
            return .skipped("không có luồng tiếng nào là URL http(s) m3u8")
        }
        let playlist = masterPlaylist(renditions: accepted, videoURI: videoURI)
        let audioDescription = accepted
            .map { (rendition: Rendition) -> String in
                guard let url = URL(string: rendition.uri) else { return "?" }
                return VideoSourceResolution.redact(url)
            }
            .joined(separator: ", ")
        return .composed(Composition(
            plan: .hlsText(playlist: playlist, baseURL: baseURL, headers: headers, subPlaylists: subPlaylists),
            audioCount: accepted.count,
            summary: "hình: \(videoLabel) \(videoDescription); tiếng: \(audioDescription)"
        ))
    }

    // MARK: - Playlist gốc tổng hợp

    private static func masterPlaylist(renditions: [Rendition], videoURI: String) -> String {
        var lines = ["#EXTM3U", "#EXT-X-VERSION:6", "#EXT-X-INDEPENDENT-SEGMENTS"]
        for (index, rendition) in renditions.enumerated() {
            var attributes = ["TYPE=AUDIO", "GROUP-ID=\"\(audioGroupId)\"", "NAME=\"\(rendition.name)\""]
            if let language = rendition.language {
                attributes.append("LANGUAGE=\"\(language)\"")
            }
            attributes.append("DEFAULT=\(index == 0 ? "YES" : "NO")")
            attributes.append("AUTOSELECT=YES")
            attributes.append("URI=\"\(rendition.uri)\"")
            lines.append("#EXT-X-MEDIA:" + attributes.joined(separator: ","))
        }
        lines.append("#EXT-X-STREAM-INF:BANDWIDTH=\(estimatedBandwidth),AUDIO=\"\(audioGroupId)\"")
        lines.append(videoURI)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Luồng tiếng dùng được theo thứ tự `audios`: URL tuyệt đối đã làm sạch escape, có dấu hiệu HLS, không trùng nhau
    /// lẫn trùng luồng hình. `NAME` bắt buộc khác nhau trong cùng nhóm ⇒ "Audio", "Audio (2)"…
    private static func renditions(
        of audios: [VideoAudioTrack],
        relativeTo base: URL?,
        excluding videoURI: String
    ) -> [Rendition] {
        var seenURIs: Set<String> = [videoURI]
        var usedNames = Set<String>()
        var result: [Rendition] = []
        for audio in audios {
            guard let url = VideoSourceResolver.webURL(VideoSourceResolver.urlText(audio.data), relativeTo: base),
                  hasHLSHint(url: url, type: audio.type) else { continue }
            let uri = url.absoluteString
            guard isSafeURI(uri), seenURIs.insert(uri).inserted else { continue }
            let name = uniqueName(quotedText(audio.label) ?? "Audio \(result.count + 1)", used: &usedNames)
            result.append(Rendition(name: name, language: languageTag(audio.language), uri: uri))
        }
        return result
    }

    // MARK: - Tiện ích

    /// Đuôi path `.m3u8`/`.m3u` hoặc gợi ý kiểu (`mimeType`/`type`) chứa `mpegurl`/`m3u`.
    private static func hasHLSHint(url: URL, type: String?) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "m3u8" || ext == "m3u" { return true }
        let hint = (type ?? "").lowercased()
        return hint.contains("mpegurl") || hint.contains("m3u")
    }

    /// AVFoundation chỉ có một bộ header cho cả asset: header của track thắng, header riêng của các luồng tiếng chỉ bổ
    /// sung khoá còn thiếu (phần tử trước thắng phần tử sau; so khoá không phân biệt hoa thường).
    private static func mergedHeaders(_ track: VideoTrack) -> [String: String] {
        var merged = track.headers
        for audio in track.audios where !audio.headers.isEmpty {
            merged = VideoSourceResolver.merge(audio.headers, overriddenBy: merged)
        }
        return merged
    }

    /// Chuỗi trong dấu nháy của thuộc tính HLS không có cơ chế escape và không được chứa `"`, CR, LF ⇒ đổi `"` thành
    /// `'`, ký tự xuống dòng/tab thành dấu cách. Rỗng ⇒ `nil`.
    private static func quotedText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: "\"", with: "'")
            .components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func languageTag(_ raw: String?) -> String? {
        guard let tag = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty,
              let regex = languageRegex else { return nil }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        return regex.firstMatch(in: tag, options: [], range: range) == nil ? nil : tag
    }

    /// URI nằm trong `URI="…"` hoặc trên một dòng riêng của playlist: không được chứa `"` hay xuống dòng.
    private static func isSafeURI(_ uri: String) -> Bool {
        !uri.isEmpty && !uri.contains("\"") && uri.rangeOfCharacter(from: .newlines) == nil
    }

    private static func uniqueName(_ base: String, used: inout Set<String>) -> String {
        var candidate = base
        var counter = 1
        while used.contains(candidate) {
            counter += 1
            candidate = "\(base) (\(counter))"
        }
        used.insert(candidate)
        return candidate
    }
}
