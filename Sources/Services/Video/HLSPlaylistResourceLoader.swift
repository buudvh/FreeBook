import AVFoundation
import Foundation

/// Phục vụ playlist HLS dạng **text** (track `native` trả `#EXTM3U` hoặc URI `data:`) cho AVPlayer qua scheme riêng
/// `fbhls://`. AVPlayer chỉ nạp playlist qua delegate; segment, playlist con và khoá đều phải là URL http(s) thật,
/// nên mọi URI tương đối trong playlist được viết lại thành tuyệt đối theo `baseURL` (host của track) ngay lúc tạo.
public final class HLSPlaylistResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    static let scheme = "fbhls"

    private let playlistData: Data
    /// Path của URL `fbhls://` duy nhất được phục vụ; URI tương đối còn sót (thiếu `baseURL`) cũng rơi vào scheme
    /// `fbhls` và phải bị từ chối thay vì trả nhầm nội dung playlist.
    private let playlistPath: String
    private let queue = DispatchQueue(label: "FreeBook.HLSPlaylistResourceLoader")

    private init(playlistData: Data, playlistPath: String) {
        self.playlistData = playlistData
        self.playlistPath = playlistPath
        super.init()
    }

    /// Dựng asset phát playlist text. `headers` đi vào `AVURLAssetHTTPHeaderFieldsKey` để áp cho mọi request http(s)
    /// của asset (playlist con, segment, khoá).
    /// Caller PHẢI giữ strong reference tới loader chừng nào asset còn dùng (resource loader chỉ giữ delegate weak).
    public static func makeAsset(
        playlist: String,
        baseURL: URL?,
        headers: [String: String]
    ) -> (asset: AVURLAsset, loader: HLSPlaylistResourceLoader) {
        // HLS bắt buộc `#EXTM3U` ở dòng đầu: playlist dựng bằng template string của JS hay có xuống dòng/thụt lề đầu.
        let text = VideoDataURI.decode(playlist)?.text ?? playlist
        let body = VideoDataURI.stripBOM(text).trimmingCharacters(in: .whitespacesAndNewlines)
        let rewritten = rewritePlaylist(body, baseURL: baseURL)

        // Đuôi `.m3u8` để AVFoundation nhận diện HLS ngay từ URL.
        var components = URLComponents()
        components.scheme = scheme
        components.host = "playlist"
        components.path = "/\(UUID().uuidString).m3u8"
        let url = components.url ?? URL(fileURLWithPath: "/invalid.m3u8")
        let loader = HLSPlaylistResourceLoader(playlistData: Data(rewritten.utf8), playlistPath: url.path)

        var options: [String: Any] = [:]
        if !headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }
        let asset = AVURLAsset(url: url, options: options)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        return (asset, loader)
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let url = loadingRequest.request.url, url.scheme?.lowercased() == Self.scheme else { return false }
        guard url.path == playlistPath else {
            AppLogger.shared.log("❌ [HLSPlaylistResourceLoader] Playlist có URI tương đối nhưng track không có host: \(url.lastPathComponent)")
            loadingRequest.finishLoading(with: NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return true
        }

        // Cố ý không điền `contentInformationRequest`: playlist nhận diện qua đuôi `.m3u8` của URL, giống mẫu
        // resource loader HLS chạy được (chỉ `respond(with:)` + `finishLoading()`); điền sai UTI có thể làm hỏng phát.
        if let dataRequest = loadingRequest.dataRequest {
            let total = playlistData.count
            let start = min(max(0, Int(dataRequest.requestedOffset)), total)
            let end: Int
            if dataRequest.requestsAllDataToEndOfResource {
                end = total
            } else {
                end = min(total, start + max(0, dataRequest.requestedLength))
            }
            if start < end {
                dataRequest.respond(with: playlistData.subdata(in: start..<end))
            }
        }
        loadingRequest.finishLoading()
        return true
    }

    // MARK: - Viết lại URI

    /// Dòng URI (không bắt đầu bằng `#`) và thuộc tính `URI="…"` trong tag (`EXT-X-KEY`, `EXT-X-MAP`, `EXT-X-MEDIA`,
    /// `EXT-X-I-FRAME-STREAM-INF`, `EXT-X-SESSION-KEY`, `EXT-X-PART`…) được resolve thành URL tuyệt đối.
    static func rewritePlaylist(_ playlist: String, baseURL: URL?) -> String {
        let normalized = playlist
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // Bỏ thụt lề mọi dòng: dòng tag thụt lề không bắt đầu bằng `#` sẽ bị AVPlayer coi là URI.
        let lines = normalized.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return "" }
            if trimmed.hasPrefix("#") {
                return rewriteURIAttributes(in: trimmed, baseURL: baseURL)
            }
            return absolutize(trimmed, baseURL: baseURL)
        }
        return lines.joined(separator: "\n")
    }

    private static let uriAttributeRegex = try? NSRegularExpression(pattern: #"URI="([^"]*)""#, options: [])

    private static func rewriteURIAttributes(in line: String, baseURL: URL?) -> String {
        guard let regex = uriAttributeRegex else { return line }
        let source = line as NSString
        let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return line }
        let result = NSMutableString(string: line)
        // Thay từ cuối lên để range của các match trước không bị lệch.
        for match in matches.reversed() {
            let valueRange = match.range(at: 1)
            guard valueRange.location != NSNotFound else { continue }
            let value = source.substring(with: valueRange)
            let rewritten = absolutize(value, baseURL: baseURL)
            if rewritten != value {
                result.replaceCharacters(in: valueRange, with: rewritten)
            }
        }
        return result as String
    }

    /// Giữ nguyên URI đã có scheme (http, https, data, skd…); `//host/…` thêm `https:`; còn lại resolve theo `baseURL`
    /// (không có `baseURL` thì để nguyên — AVPlayer sẽ báo lỗi segment, ext phải trả `host`).
    static func absolutize(_ uri: String, baseURL: URL?) -> String {
        guard !uri.isEmpty else { return uri }
        if uri.hasPrefix("//") {
            return "https:" + uri
        }
        if let url = URL(string: uri), let scheme = url.scheme, !scheme.isEmpty {
            return uri
        }
        guard let baseURL, let resolved = URL(string: uri, relativeTo: baseURL)?.absoluteURL else { return uri }
        return resolved.absoluteString
    }
}
