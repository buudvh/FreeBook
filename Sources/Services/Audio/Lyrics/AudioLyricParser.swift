import Foundation

/// Đọc nội dung lời bài hát thành `AudioLyrics`; định dạng tự nhận từ nội dung (hợp đồng tiện ích: `type` chỉ tham khảo):
/// - **LRC**: có dòng mở đầu bằng nhãn thời gian `[mm:ss]`, `[mm:ss.xx]`, `[mm:ss:xx]` (phút có thể > 59). Một dòng nhiều
///   nhãn ⇒ một dòng lời cho mỗi nhãn. `[offset:±ms]`: dương = lời hiện **sớm** hơn (thời điểm − offset). Bỏ nhãn meta
///   (`[ti:]`, `[ar:]`, `[al:]`, `[by:]`, `[length:]`… mọi nhãn không phải thời gian) và nhãn từng chữ `<mm:ss.xx>`; dòng
///   không có nhãn thời gian bị bỏ. Sắp theo thời gian (giữ thứ tự gốc khi trùng).
/// - **VTT / SRT**: có dòng `-->` ⇒ `VideoSubtitleParser.parse`; mỗi cue = một dòng, `time` = mốc bắt đầu.
/// - Còn lại: **chữ thường** không mốc giờ — `<br>` / `</p>` thành xuống dòng, bỏ thẻ HTML, giải entity cơ bản, gộp nhiều
///   dòng trống liền nhau thành một (ngăn đoạn).
enum AudioLyricParser {
    static func parse(_ raw: String) -> AudioLyrics {
        let text = VideoDataURI.stripBOM(raw)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = text.components(separatedBy: "\n")
        if lines.contains(where: { isTimedLRCLine($0) }) {
            return AudioLyrics(lines: parseLRC(lines))
        }
        if text.contains("-->") {
            let cues = VideoSubtitleParser.parse(text)
            if !cues.isEmpty {
                return AudioLyrics(lines: cues.map { AudioLyricLine(time: $0.start, text: $0.text) })
            }
        }
        return AudioLyrics(lines: parsePlain(text))
    }

    // MARK: - LRC

    /// `[mm:ss]` / `[mm:ss.xx]` / `[mm:ss:xx]` ở đầu dòng (cho phép khoảng trắng trước).
    private static let leadingTimeTag = try? NSRegularExpression(pattern: #"^\s*\[\d{1,4}:\d{1,2}(?:[.:]\d{1,3})?\]"#, options: [])
    /// Một nhãn `[...]` bất kỳ ở đầu phần còn lại của dòng.
    private static let leadingTag = try? NSRegularExpression(pattern: #"^\s*\[([^\[\]]*)\]"#, options: [])
    private static let wordTimeTag = try? NSRegularExpression(pattern: #"<\d{1,4}:\d{1,2}(?:[.:]\d{1,3})?>"#, options: [])

    private static func isTimedLRCLine(_ line: String) -> Bool {
        guard let regex = leadingTimeTag else { return false }
        return regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..<line.endIndex, in: line)) != nil
    }

    private static func parseLRC(_ lines: [String]) -> [AudioLyricLine] {
        var offsetSeconds: Double = 0
        var entries: [(time: Double, order: Int, text: String)] = []
        for line in lines {
            var rest = Substring(line)
            var times: [Double] = []
            while let tag = nextTag(in: rest) {
                rest = rest[tag.end...]
                if let seconds = timestamp(tag.content) {
                    times.append(seconds)
                } else if let offset = offsetValue(tag.content) {
                    offsetSeconds = offset
                }
                // Nhãn meta khác (`ti`, `ar`, `al`, `by`, `length`…) ⇒ bỏ.
            }
            guard !times.isEmpty else { continue }
            let lyric = removingWordTags(String(rest)).trimmingCharacters(in: .whitespaces)
            for time in times {
                entries.append((time: time, order: entries.count, text: lyric))
            }
        }
        return entries
            .sorted { $0.time == $1.time ? $0.order < $1.order : $0.time < $1.time }
            .map { AudioLyricLine(time: max(0, $0.time - offsetSeconds), text: $0.text) }
    }

    private static func nextTag(in text: Substring) -> (content: String, end: Substring.Index)? {
        guard let regex = leadingTag else { return nil }
        let string = String(text)
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range),
              let whole = Range(match.range, in: string),
              let inner = Range(match.range(at: 1), in: string) else { return nil }
        let consumed = string.distance(from: string.startIndex, to: whole.upperBound)
        return (String(string[inner]), text.index(text.startIndex, offsetBy: consumed))
    }

    /// `mm:ss`, `mm:ss.xx`, `mm:ss:xx` (phần sau dấu `.`/`:` thứ hai là phần lẻ của giây).
    private static func timestamp(_ content: String) -> Double? {
        let parts = content.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 || parts.count == 3,
              let minutes = Int(parts[0].trimmingCharacters(in: .whitespaces)), minutes >= 0 else { return nil }
        let secondsText: String
        if parts.count == 3 {
            secondsText = "\(parts[1]).\(parts[2])"
        } else {
            secondsText = parts[1]
        }
        guard let seconds = Double(secondsText.trimmingCharacters(in: .whitespaces)), seconds >= 0, seconds < 60 else {
            return nil
        }
        return Double(minutes) * 60 + seconds
    }

    /// `offset:+500` / `offset:-200` (mili-giây) ⇒ giây.
    private static func offsetValue(_ content: String) -> Double? {
        let parts = content.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "offset",
              let milliseconds = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        return milliseconds / 1000
    }

    private static func removingWordTags(_ text: String) -> String {
        guard let regex = wordTimeTag else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    // MARK: - Chữ thường

    private static let lineBreakTag = try? NSRegularExpression(pattern: #"<\s*br\s*/?\s*>|<\s*/\s*(?:p|div|li)\s*>"#, options: [.caseInsensitive])
    private static let anyTag = try? NSRegularExpression(pattern: #"<[^>]*>"#, options: [])

    private static func parsePlain(_ text: String) -> [AudioLyricLine] {
        var cleaned = text
        if let lineBreakTag {
            cleaned = lineBreakTag.stringByReplacingMatches(
                in: cleaned, options: [], range: NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned), withTemplate: "\n"
            )
        }
        if let anyTag {
            cleaned = anyTag.stringByReplacingMatches(
                in: cleaned, options: [], range: NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned), withTemplate: ""
            )
        }
        let entities = [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&")]
        for (entity, replacement) in entities {
            cleaned = cleaned.replacingOccurrences(of: entity, with: replacement)
        }
        var result: [AudioLyricLine] = []
        for line in cleaned.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                // Gộp dòng trống liền nhau; bỏ dòng trống ở đầu.
                guard let last = result.last, !last.text.isEmpty else { continue }
            }
            result.append(AudioLyricLine(time: nil, text: trimmed))
        }
        while result.last?.text.isEmpty == true {
            result.removeLast()
        }
        return result
    }
}
