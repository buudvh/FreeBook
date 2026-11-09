import Foundation

/// Lấy nội dung một nguồn lời (`AudioLyricSource.data`) rồi đọc thành `AudioLyrics` (`AudioLyricParser`):
/// - URI `data:` (base64 hoặc percent-encoded) ⇒ giải bằng `VideoDataURI.decode`;
/// - URL http(s) một dòng ⇒ tải bằng `URLSession` kèm `headers` của track (Referer, cookie…), UA Safari khi track không khai;
/// - còn lại ⇒ chính `data` là nội dung lời.
///
/// Chạy ngoài main (hàm `async` không gắn actor). Log lỗi chỉ ghi tên nguồn lời + host, không ghi URL đầy đủ (có thể mang
/// token).
enum AudioLyricLoader {
    enum LoadError: LocalizedError {
        case emptyData
        case httpStatus(Int)
        case undecodable
        case noLines

        var errorDescription: String? {
            switch self {
            case .emptyData:
                return "Nguồn lời không có dữ liệu."
            case .httpStatus(let code):
                return "Không tải được lời bài hát (HTTP \(code))."
            case .undecodable:
                return "Không đọc được nội dung lời bài hát."
            case .noLines:
                return "Lời bài hát trống."
            }
        }
    }

    private static let requestTimeout: TimeInterval = 20
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static func load(_ source: AudioLyricSource, headers: [String: String]) async throws -> AudioLyrics {
        let probe = source.data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !probe.isEmpty else { throw LoadError.emptyData }
        var origin = "nội dung trực tiếp"
        do {
            let text: String
            if VideoDataURI.isDataURI(probe) {
                origin = "URI data:"
                guard let decoded = VideoDataURI.decode(probe) else { throw LoadError.undecodable }
                text = decoded.text
            } else if let url = remoteURL(probe) {
                origin = "tải từ \(url.host ?? "?")"
                text = try await download(url, headers: headers)
            } else {
                text = source.data
            }
            try Task.checkCancellation()
            let lyrics = AudioLyricParser.parse(text)
            guard lyrics.lines.contains(where: { !$0.text.isEmpty }) else { throw LoadError.noLines }
            return lyrics
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            AppLogger.shared.log("❌ [AudioPlayer] Lời bài hát «\(source.displayLabel)» (\(origin)) lỗi: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Nội bộ

    private static func remoteURL(_ probe: String) -> URL? {
        let candidate = probe.hasPrefix("//") ? "https:" + probe : probe
        guard !candidate.contains("\n"), !candidate.contains(" "), let url = URL(string: candidate) else { return nil }
        let scheme = url.scheme?.lowercased()
        return (scheme == "http" || scheme == "https") && url.host != nil ? url : nil
    }

    private static func download(_ url: URL, headers: [String: String]) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LoadError.httpStatus(http.statusCode)
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        return TextEncodingDecoder.decode(data)
    }
}
