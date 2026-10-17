import Foundation

/// Tải và parse phụ đề của track video (`subtitles: [{data, type, label, language}]`). Theo DOC chỉ VTT và SRT;
/// `data` có thể là URL, URI `data:` hoặc nội dung phụ đề viết thẳng.
public enum VideoSubtitleParser {
    public enum LoadError: LocalizedError {
        case emptyData
        case httpStatus(Int)
        case noCues

        public var errorDescription: String? {
            switch self {
            case .emptyData:
                return "Phụ đề không có dữ liệu."
            case .httpStatus(let code):
                return "Không tải được phụ đề (HTTP \(code))."
            case .noCues:
                return "Không đọc được phụ đề (chỉ hỗ trợ SRT/WebVTT)."
            }
        }
    }

    private static let requestTimeout: TimeInterval = 20
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// `headers` là header của track (Referer…); áp khi `data` là URL http(s).
    public static func load(_ track: VideoSubtitleTrack, headers: [String: String]) async throws -> [VideoSubtitleCue] {
        let probe = track.data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !probe.isEmpty else { throw LoadError.emptyData }
        let label = track.label ?? track.language ?? "?"
        do {
            let text: String
            if VideoDataURI.isDataURI(probe) {
                guard let decoded = VideoDataURI.decode(probe) else { throw LoadError.noCues }
                text = decoded.text
            } else if let url = remoteURL(probe) {
                text = try await download(url, headers: headers)
            } else {
                text = track.data
            }
            let cues = parse(text)
            guard !cues.isEmpty else { throw LoadError.noCues }
            return cues
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLogger.shared.log("❌ [VideoSubtitleParser] Phụ đề \"\(label)\" lỗi: \(error.localizedDescription)")
            throw error
        }
    }

    /// Parse SRT hoặc WebVTT (tự nhận dạng theo dòng thời gian `-->`), sắp theo thời điểm bắt đầu.
    public static func parse(_ text: String) -> [VideoSubtitleCue] {
        let normalized = VideoDataURI.stripBOM(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var cues: [VideoSubtitleCue] = []
        var block: [String] = []

        func flush() {
            defer { block.removeAll(keepingCapacity: true) }
            if let parsed = cue(from: block) { cues.append(parsed) }
        }

        for line in normalized.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else {
                block.append(line)
            }
        }
        flush()
        return cues.sorted { $0.start < $1.start }
    }

    // MARK: - Nội bộ

    private static func remoteURL(_ probe: String) -> URL? {
        let candidate = probe.hasPrefix("//") ? "https:" + probe : probe
        guard !candidate.contains("\n"), let url = URL(string: candidate) else { return nil }
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

    /// Một khối = các dòng liền nhau; khối không có dòng `-->` (WEBVTT, NOTE, STYLE, REGION) bị bỏ qua.
    private static func cue(from block: [String]) -> VideoSubtitleCue? {
        guard let timingIndex = block.firstIndex(where: { $0.contains("-->") }) else { return nil }
        let parts = block[timingIndex].components(separatedBy: "-->")
        guard parts.count >= 2,
              let start = timestamp(parts[0]),
              let end = timestamp(firstToken(of: parts[1])),
              end > start else { return nil }
        let text = block[(timingIndex + 1)...]
            .map { cleanText($0) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !text.isEmpty else { return nil }
        return VideoSubtitleCue(start: start, end: end, text: text)
    }

    /// Bỏ cue settings của VTT phía sau mốc kết thúc (`00:01.000 align:start position:10%`).
    private static func firstToken(of value: String) -> String {
        value.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .first.map(String.init) ?? ""
    }

    /// `hh:mm:ss,mmm` (SRT), `hh:mm:ss.mmm` / `mm:ss.mmm` (VTT); phần mili-giây có thể thiếu hoặc ngắn hơn 3 chữ số.
    private static func timestamp(_ raw: String) -> TimeInterval? {
        let value = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !value.isEmpty else { return nil }
        let fields = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (2...3).contains(fields.count) else { return nil }
        var seconds: TimeInterval = 0
        for (index, field) in fields.enumerated() {
            let isLast = index == fields.count - 1
            guard let number = isLast ? Double(field) : Double(Int(field) ?? -1), number >= 0 else { return nil }
            seconds = seconds * 60 + number
        }
        return seconds
    }

    private static let tagRegex = try? NSRegularExpression(pattern: #"<[^>]*>|\{\\[^}]*\}"#, options: [])

    private static func cleanText(_ line: String) -> String {
        var text = line
        if let regex = tagRegex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        let entities = [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
