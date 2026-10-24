import Foundation

/// Phân tích playlist HLS và lập kế hoạch tải offline cho `VideoHLSDownloader` — thuần, không gọi mạng:
/// - `parseMaster`: biến thể (`EXT-X-STREAM-INF`) + rendition (`EXT-X-MEDIA`).
/// - `planMedia`: tài nguyên cần tải theo thứ tự (khoá, init, đoạn) + playlist local đã thay URI bằng tên file.
/// - `masterPlaylist`: playlist gốc local một biến thể (+ tối đa một luồng tiếng).
///
/// Mọi URI trong playlist local là **tên file cùng thư mục** — chỉ URL mở đầu mang cổng/token của
/// `VideoOfflineHTTPServer`, server đổi cổng chỉ cần dựng lại URL item. Byterange được tách thành file riêng (bỏ tag
/// `BYTERANGE`); `EXT-X-MEDIA-SEQUENCE` giữ nguyên để IV ngầm của AES-128 vẫn đúng. Byte của đoạn giữ nguyên văn.
enum VideoHLSOfflinePlanner {
    enum PlanError: LocalizedError {
        case notPlaylist
        case live
        case empty
        case unsupportedEncryption(String)

        var errorDescription: String? {
            switch self {
            case .notPlaylist: return "Dữ liệu tải về không phải playlist HLS."
            case .live: return "Đây là luồng phát trực tiếp, không tải về được."
            case .empty: return "Playlist không có đoạn video nào."
            case .unsupportedEncryption(let method): return "Video được mã hoá kiểu \(method) (DRM), không tải về được."
            }
        }
    }

    struct Variant: Sendable {
        let uri: String
        let bandwidth: Int
        let averageBandwidth: Int?
        let width: Int
        let height: Int
        let codecs: String?
        let frameRate: String?
        let audioGroup: String?

        var label: String {
            if height > 0 { return "\(height)p" }
            return bandwidth > 0 ? String(format: "%.1f Mbps", Double(bandwidth) / 1_000_000) : ""
        }
    }

    struct Rendition: Sendable {
        let type: String
        let groupId: String
        let name: String?
        let language: String?
        let uri: String?
        let isDefault: Bool
    }

    struct Master: Sendable {
        let variants: [Variant]
        let renditions: [Rendition]

        /// Luồng tiếng tách riêng của nhóm `AUDIO` của biến thể: `DEFAULT=YES` trước, không thì cái đầu có URI.
        /// `nil` khi tiếng nằm chung trong luồng hình.
        func audioRendition(for variant: Variant) -> Rendition? {
            guard let group = variant.audioGroup else { return nil }
            let candidates = renditions.filter { $0.type == "AUDIO" && $0.groupId == group && $0.uri != nil }
            return candidates.first { $0.isDefault } ?? candidates.first
        }
    }

    struct ByteRange: Sendable, Equatable {
        let offset: Int64
        let length: Int64
    }

    struct Resource: Sendable {
        enum Role: Sendable {
            case segment
            case initSegment
            case key
        }

        let url: URL
        let byteRange: ByteRange?
        let fileName: String
        let role: Role
    }

    struct MediaPlan: Sendable {
        let playlist: String
        let resources: [Resource]
        let segmentCount: Int
        /// Nhận diện nguồn **không gồm query** (token đổi giữa các lượt phân giải link) — để tải tiếp bản dở.
        let signatureSource: String
    }

    // MARK: - Nhận diện

    static func isPlaylist(_ text: String) -> Bool {
        body(of: text).hasPrefix("#EXTM3U")
    }

    static func isMaster(_ text: String) -> Bool {
        body(of: text).contains("#EXT-X-STREAM-INF")
    }

    /// Playlist gốc có khoá phiên kiểu DRM (`EXT-X-SESSION-KEY` không phải AES-128) — chặn sớm trước khi tải gì.
    static func sessionKeyMethod(in text: String) -> String? {
        for line in lines(of: text) where line.hasPrefix("#EXT-X-SESSION-KEY:") {
            let method = attributes(String(line.dropFirst("#EXT-X-SESSION-KEY:".count)))["METHOD"]?.uppercased() ?? ""
            if method != "AES-128" && method != "NONE" { return method }
        }
        return nil
    }

    // MARK: - Playlist gốc

    static func parseMaster(_ text: String, baseURL: URL?) -> Master {
        var variants: [Variant] = []
        var renditions: [Rendition] = []
        var pendingAttributes: [String: String]?
        for line in lines(of: text) {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                pendingAttributes = attributes(String(line.dropFirst("#EXT-X-STREAM-INF:".count)))
            } else if line.hasPrefix("#EXT-X-MEDIA:") {
                let attrs = attributes(String(line.dropFirst("#EXT-X-MEDIA:".count)))
                renditions.append(Rendition(
                    type: attrs["TYPE"]?.uppercased() ?? "",
                    groupId: attrs["GROUP-ID"] ?? "",
                    name: attrs["NAME"],
                    language: attrs["LANGUAGE"],
                    uri: attrs["URI"].map { HLSPlaylistResourceLoader.absolutize($0, baseURL: baseURL) },
                    isDefault: attrs["DEFAULT"]?.uppercased() == "YES"
                ))
            } else if !line.hasPrefix("#"), let attrs = pendingAttributes {
                pendingAttributes = nil
                let resolution = attrs["RESOLUTION"]?.lowercased().split(separator: "x").compactMap { Int($0) } ?? []
                variants.append(Variant(
                    uri: HLSPlaylistResourceLoader.absolutize(line, baseURL: baseURL),
                    bandwidth: Int(attrs["BANDWIDTH"] ?? "") ?? 0,
                    averageBandwidth: Int(attrs["AVERAGE-BANDWIDTH"] ?? ""),
                    width: resolution.count == 2 ? resolution[0] : 0,
                    height: resolution.count == 2 ? resolution[1] : 0,
                    codecs: attrs["CODECS"],
                    frameRate: attrs["FRAME-RATE"],
                    audioGroup: attrs["AUDIO"]
                ))
            }
        }
        return Master(variants: variants, renditions: renditions)
    }

    /// Playlist gốc local: một `EXT-X-STREAM-INF` trỏ `videoFile`, kèm một `EXT-X-MEDIA TYPE=AUDIO` trỏ `audioFile`.
    static func masterPlaylist(variant: Variant, audio: Rendition?, videoFile: String, audioFile: String?) -> String {
        var lines = ["#EXTM3U"]
        var streamAttributes = ["BANDWIDTH=\(variant.bandwidth > 0 ? variant.bandwidth : 1_000_000)"]
        if let average = variant.averageBandwidth, average > 0 {
            streamAttributes.append("AVERAGE-BANDWIDTH=\(average)")
        }
        if variant.width > 0, variant.height > 0 {
            streamAttributes.append("RESOLUTION=\(variant.width)x\(variant.height)")
        }
        if let codecs = variant.codecs, !codecs.isEmpty {
            streamAttributes.append("CODECS=\"\(quotedSafe(codecs))\"")
        }
        if let frameRate = variant.frameRate, !frameRate.isEmpty {
            streamAttributes.append("FRAME-RATE=\(frameRate)")
        }
        if let audio, let audioFile {
            var mediaAttributes = ["TYPE=AUDIO", "GROUP-ID=\"aud\"", "NAME=\"\(quotedSafe(audio.name ?? "Âm thanh"))\""]
            if let language = audio.language, !language.isEmpty {
                mediaAttributes.append("LANGUAGE=\"\(quotedSafe(language))\"")
            }
            mediaAttributes += ["DEFAULT=YES", "AUTOSELECT=YES", "URI=\"\(audioFile)\""]
            lines.append("#EXT-X-MEDIA:" + mediaAttributes.joined(separator: ","))
            streamAttributes.append("AUDIO=\"aud\"")
        }
        lines.append("#EXT-X-STREAM-INF:" + streamAttributes.joined(separator: ","))
        lines.append(videoFile)
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Playlist con

    /// `filePrefix` tách tên file của luồng hình (`v`) và luồng tiếng (`a`) trong cùng thư mục tập.
    static func planMedia(_ text: String, baseURL: URL?, filePrefix: String) throws -> MediaPlan {
        let allLines = lines(of: text)
        guard allLines.first?.hasPrefix("#EXTM3U") == true else { throw PlanError.notPlaylist }

        var output: [String] = []
        var resources: [Resource] = []
        var keyFiles: [String: String] = [:]
        var mapFiles: [String: String] = [:]
        var rangeEnds: [String: Int64] = [:]
        var pendingRange: (length: Int64, offset: Int64?)?
        var segmentCount = 0
        var isFragmentedMP4 = false
        var hasEndList = false
        var isVOD = false

        for line in allLines {
            if line.hasPrefix("#EXT-X-KEY:") {
                let attrs = attributes(String(line.dropFirst("#EXT-X-KEY:".count)))
                let method = attrs["METHOD"]?.uppercased() ?? "NONE"
                if method == "NONE" {
                    output.append(line)
                    continue
                }
                let keyFormat = attrs["KEYFORMAT"]?.lowercased() ?? "identity"
                // Khoá nhúng thẳng bằng URI `data:` ⇒ giữ nguyên dòng, không có gì để tải.
                if method == "AES-128", keyFormat == "identity", attrs["URI"].map(VideoDataURI.isDataURI) == true {
                    output.append(line)
                    continue
                }
                guard method == "AES-128", keyFormat == "identity",
                      let rawURI = attrs["URI"],
                      let url = resolvedURL(rawURI, baseURL: baseURL) else {
                    throw PlanError.unsupportedEncryption(method)
                }
                let fileName: String
                if let existing = keyFiles[url.absoluteString] {
                    fileName = existing
                } else {
                    fileName = "\(filePrefix)k\(keyFiles.count + 1).key"
                    keyFiles[url.absoluteString] = fileName
                    resources.append(Resource(url: url, byteRange: nil, fileName: fileName, role: .key))
                }
                var rebuilt = "#EXT-X-KEY:METHOD=AES-128,URI=\"\(fileName)\""
                if let iv = attrs["IV"], !iv.isEmpty { rebuilt += ",IV=\(iv)" }
                output.append(rebuilt)
            } else if line.hasPrefix("#EXT-X-MAP:") {
                let attrs = attributes(String(line.dropFirst("#EXT-X-MAP:".count)))
                guard let rawURI = attrs["URI"], let url = resolvedURL(rawURI, baseURL: baseURL) else {
                    throw PlanError.notPlaylist
                }
                let range = attrs["BYTERANGE"].flatMap { parseByteRange($0) }.map {
                    ByteRange(offset: $0.offset ?? 0, length: $0.length)
                }
                let mapKey = url.absoluteString + (range.map { "#\($0.offset)-\($0.length)" } ?? "")
                let fileName: String
                if let existing = mapFiles[mapKey] {
                    fileName = existing
                } else {
                    fileName = "\(filePrefix)i\(mapFiles.count + 1).mp4"
                    mapFiles[mapKey] = fileName
                    resources.append(Resource(url: url, byteRange: range, fileName: fileName, role: .initSegment))
                }
                isFragmentedMP4 = true
                output.append("#EXT-X-MAP:URI=\"\(fileName)\"")
            } else if line.hasPrefix("#EXT-X-BYTERANGE:") {
                pendingRange = parseByteRange(String(line.dropFirst("#EXT-X-BYTERANGE:".count)))
            } else if line.hasPrefix("#EXT-X-ENDLIST") {
                hasEndList = true
                output.append(line)
            } else if line.hasPrefix("#EXT-X-PLAYLIST-TYPE:") {
                isVOD = line.uppercased().hasSuffix("VOD")
                output.append(line)
            } else if droppedTagPrefixes.contains(where: { line.hasPrefix($0) }) {
                continue
            } else if line.hasPrefix("#") {
                output.append(line)
            } else {
                guard let url = resolvedURL(line, baseURL: baseURL) else { throw PlanError.notPlaylist }
                var range: ByteRange?
                if let pending = pendingRange {
                    let offset = pending.offset ?? rangeEnds[url.absoluteString] ?? 0
                    range = ByteRange(offset: offset, length: pending.length)
                    rangeEnds[url.absoluteString] = offset + pending.length
                    pendingRange = nil
                }
                segmentCount += 1
                let fileName = String(format: "%@s%05d.%@", filePrefix, segmentCount, segmentExtension(for: url, isFragmentedMP4: isFragmentedMP4))
                resources.append(Resource(url: url, byteRange: range, fileName: fileName, role: .segment))
                output.append(fileName)
            }
        }

        guard hasEndList || isVOD else { throw PlanError.live }
        guard segmentCount > 0 else { throw PlanError.empty }
        if !hasEndList { output.append("#EXT-X-ENDLIST") }

        let signature = resources.map { resource -> String in
            let range = resource.byteRange.map { "@\($0.offset)+\($0.length)" } ?? ""
            return "\(resource.fileName)=\(stableIdentity(of: resource.url))\(range)"
        }.joined(separator: "\n")
        return MediaPlan(
            playlist: output.joined(separator: "\n") + "\n",
            resources: resources,
            segmentCount: segmentCount,
            signatureSource: signature
        )
    }

    // MARK: - Tiện ích

    /// Tag không có nghĩa với bản VOD trên máy (low-latency, chỉ báo của server).
    private static let droppedTagPrefixes = [
        "#EXT-X-PART:", "#EXT-X-PART-INF:", "#EXT-X-PRELOAD-HINT:", "#EXT-X-SERVER-CONTROL:",
        "#EXT-X-RENDITION-REPORT:", "#EXT-X-SKIP:", "#EXT-X-I-FRAME-STREAM-INF:"
    ]

    /// Đuôi file theo vai trò: giữ đuôi media quen thuộc của URL; đuôi giả (`.jpg`, `.png`, `.html`… nguồn hay ngụy trang)
    /// ⇒ `.m4s` cho fMP4, `.ts` cho còn lại. Byte giữ nguyên văn.
    private static func segmentExtension(for url: URL, isFragmentedMP4: Bool) -> String {
        switch url.pathExtension.lowercased() {
        case "ts", "mts": return "ts"
        case "aac": return "aac"
        case "mp3": return "mp3"
        case "ac3": return "ac3"
        case "ec3": return "ec3"
        case "m4a": return "m4a"
        case "m4s", "mp4", "m4v", "cmfv", "cmfa": return "m4s"
        default: return isFragmentedMP4 ? "m4s" : "ts"
        }
    }

    private static func resolvedURL(_ uri: String, baseURL: URL?) -> URL? {
        let absolute = HLSPlaylistResourceLoader.absolutize(uri, baseURL: baseURL)
        guard let url = URL(string: absolute), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// `scheme://host/path` — bỏ query/fragment (thường chứa token hết hạn).
    private static func stableIdentity(of url: URL) -> String {
        "\(url.scheme ?? "")://\(url.host ?? "")\(url.path)"
    }

    /// `n[@o]`.
    private static func parseByteRange(_ raw: String) -> (length: Int64, offset: Int64?)? {
        let parts = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")).split(separator: "@")
        guard let first = parts.first, let length = Int64(first), length > 0 else { return nil }
        let offset = parts.count > 1 ? Int64(parts[1]) : nil
        return (length, offset)
    }

    /// Danh sách thuộc tính `KEY=VALUE,KEY="VALUE, có phẩy"` ⇒ từ điển (khoá viết hoa, giá trị bỏ nháy).
    static func attributes(_ list: String) -> [String: String] {
        var result: [String: String] = [:]
        var key = ""
        var value = ""
        var readingKey = true
        var inQuotes = false
        func commit() {
            let name = key.trimmingCharacters(in: .whitespaces).uppercased()
            if !name.isEmpty { result[name] = value.trimmingCharacters(in: .whitespaces) }
            key = ""
            value = ""
            readingKey = true
        }
        for character in list {
            if readingKey {
                if character == "=" {
                    readingKey = false
                } else if character == "," {
                    key = ""
                } else {
                    key.append(character)
                }
            } else if character == "\"" {
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                commit()
            } else {
                value.append(character)
            }
        }
        if !readingKey { commit() }
        return result
    }

    private static func quotedSafe(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " ")
    }

    private static func body(of text: String) -> String {
        let decoded = VideoDataURI.decode(text)?.text ?? text
        return VideoDataURI.stripBOM(decoded).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Chuẩn hoá xuống dòng, bỏ thụt lề và dòng trống (như `HLSPlaylistResourceLoader.rewritePlaylist`).
    private static func lines(of text: String) -> [String] {
        body(of: text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
