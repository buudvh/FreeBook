import Foundation

/// Một luồng HLS **trên máy** (playlist con đã tải trong thư mục tập, `VideoHLSDownloader`) đọc lại để xuất: danh sách đoạn
/// theo thứ tự kèm khoá AES-128, init fMP4 và byterange. Thuần đọc đĩa, không gọi mạng.
///
/// Playlist local do `VideoHLSOfflinePlanner` viết: mọi URI là tên file cùng thư mục (`resolve` chỉ nhận tên file đang có
/// trong thư mục tập), `BYTERANGE` đã tách thành file riêng (vẫn đọc nếu còn), `EXT-X-MEDIA-SEQUENCE` giữ nguyên nên IV
/// ngầm vẫn đúng. Khoá `data:` được giữ nguyên văn trong playlist — giải mã base64 ra **byte**, không qua `VideoDataURI`
/// (bản đó trả text, hỏng khoá nhị phân).
struct VideoHLSLocalStream: Sendable {
    enum StreamError: LocalizedError {
        case missingFile(String)
        case unsupportedEncryption(String)
        case invalidKey(String)
        case truncated(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .missingFile(let name): return "Thiếu file \(name) của bản tải — hãy tải lại tập này."
            case .unsupportedEncryption(let method): return "Đoạn video mã hoá kiểu \(method), không xuất được."
            case .invalidKey(let detail): return "Khoá giải mã của bản tải không hợp lệ (\(detail))."
            case .truncated(let name): return "File \(name) của bản tải bị thiếu dữ liệu — hãy tải lại tập này."
            case .empty: return "Playlist của bản tải không có đoạn video nào."
            }
        }
    }

    struct ByteRange: Sendable, Equatable {
        let offset: Int64
        let length: Int64
    }

    /// Một vùng byte cần chép (đoạn hoặc init), kèm khoá + IV đã tính sẵn khi bị mã hoá.
    struct Part: Sendable, Equatable {
        let file: URL
        let byteRange: ByteRange?
        /// 16 byte khoá AES-128; `nil` = không mã hoá.
        let key: Data?
        let iv: Data?

        var displayName: String { file.lastPathComponent }
    }

    struct Segment: Sendable {
        let part: Part
        /// Init fMP4 (`EXT-X-MAP`) đang áp dụng cho đoạn; `nil` với MPEG-TS / audio thuần.
        let initPart: Part?
    }

    let segments: [Segment]
    /// Tổng byte nguồn (đoạn + init khác nhau) — mẫu số của phần trăm tiến độ.
    let sourceBytes: Int64

    var isFragmentedMP4: Bool { segments.contains { $0.initPart != nil } }

    /// Số init khác nhau: > 1 (quảng cáo chèn qua `DISCONTINUITY` đổi init) thì file nối có thể không phát liền mạch.
    var distinctInitCount: Int {
        var seen: [Part] = []
        for initPart in segments.compactMap(\.initPart) where !seen.contains(initPart) {
            seen.append(initPart)
        }
        return seen.count
    }

    /// Đuôi file xuất: fMP4 ⇒ `mp4` (hình) / `m4a` (tiếng); audio thuần giữ đuôi gốc; còn lại MPEG-TS.
    func outputExtension(isAudio: Bool) -> String {
        if isFragmentedMP4 { return isAudio ? "m4a" : "mp4" }
        let first = segments.first?.part.file.pathExtension.lowercased() ?? ""
        switch first {
        case "aac", "mp3", "ac3", "ec3", "m4a": return first
        default: return "ts"
        }
    }

    // MARK: - Đọc playlist

    /// Playlist gốc local (`VideoHLSOfflinePlanner.masterPlaylist`): file playlist hình (dòng sau `EXT-X-STREAM-INF` đầu
    /// tiên) và playlist tiếng tách riêng (`EXT-X-MEDIA:TYPE=AUDIO,URI=…`).
    static func masterReferences(_ text: String) -> (video: String?, audio: String?) {
        var video: String?
        var audio: String?
        var expectsVariant = false
        for line in lines(of: text) {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                expectsVariant = true
            } else if line.hasPrefix("#EXT-X-MEDIA:") {
                let attrs = VideoHLSOfflinePlanner.attributes(String(line.dropFirst("#EXT-X-MEDIA:".count)))
                if audio == nil, attrs["TYPE"]?.uppercased() == "AUDIO", let uri = attrs["URI"], !uri.isEmpty {
                    audio = uri
                }
            } else if !line.hasPrefix("#"), expectsVariant, video == nil {
                video = line
                expectsVariant = false
            }
        }
        return (video, audio)
    }

    /// Playlist con → đoạn theo thứ tự. `resolve(tên)` trả file **đang có** trong thư mục tập.
    static func parse(_ text: String, resolve: (String) -> URL?) throws -> VideoHLSLocalStream {
        var mediaSequence: Int64 = 0
        var ordinal: Int64 = 0
        var key: (bytes: Data, explicitIV: Data?)?
        var currentInit: Part?
        var pendingRange: (length: Int64, offset: Int64?)?
        var rangeEnds: [URL: Int64] = [:]
        var keyCache: [String: Data] = [:]
        var segments: [Segment] = []

        for line in lines(of: text) {
            if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                mediaSequence = Int64(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count).trimmingCharacters(in: .whitespaces)) ?? 0
            } else if line.hasPrefix("#EXT-X-KEY:") {
                let attrs = VideoHLSOfflinePlanner.attributes(String(line.dropFirst("#EXT-X-KEY:".count)))
                let method = attrs["METHOD"]?.uppercased() ?? "NONE"
                if method == "NONE" {
                    key = nil
                    continue
                }
                guard method == "AES-128", let uri = attrs["URI"], !uri.isEmpty else {
                    throw StreamError.unsupportedEncryption(method)
                }
                let bytes = try keyBytes(uri, cache: &keyCache, resolve: resolve)
                key = (bytes: bytes, explicitIV: try attrs["IV"].map(parseIV))
            } else if line.hasPrefix("#EXT-X-MAP:") {
                let attrs = VideoHLSOfflinePlanner.attributes(String(line.dropFirst("#EXT-X-MAP:".count)))
                guard let uri = attrs["URI"] else { throw StreamError.missingFile("EXT-X-MAP") }
                let range = attrs["BYTERANGE"].flatMap(parseByteRange).map { ByteRange(offset: $0.offset ?? 0, length: $0.length) }
                // Init bị mã hoá khi có khoá đang áp dụng (IV phải tường minh; thiếu thì lấy số thứ tự của đoạn kế tiếp).
                // `VideoHLSStreamWriter` còn dò đầu file: init đọc được dạng hộp MP4 thì chép thẳng, không giải mã.
                currentInit = Part(
                    file: try localFile(uri, resolve: resolve),
                    byteRange: range,
                    key: key?.bytes,
                    iv: key.map { $0.explicitIV ?? sequenceIV(mediaSequence + ordinal) }
                )
            } else if line.hasPrefix("#EXT-X-BYTERANGE:") {
                pendingRange = parseByteRange(String(line.dropFirst("#EXT-X-BYTERANGE:".count)))
            } else if !line.hasPrefix("#") {
                let file = try localFile(line, resolve: resolve)
                var range: ByteRange?
                if let pending = pendingRange {
                    let offset = pending.offset ?? rangeEnds[file] ?? 0
                    range = ByteRange(offset: offset, length: pending.length)
                    rangeEnds[file] = offset + pending.length
                    pendingRange = nil
                }
                let part = Part(
                    file: file,
                    byteRange: range,
                    key: key?.bytes,
                    iv: key.map { $0.explicitIV ?? sequenceIV(mediaSequence + ordinal) }
                )
                segments.append(Segment(part: part, initPart: currentInit))
                ordinal += 1
            }
        }

        guard !segments.isEmpty else { throw StreamError.empty }
        var inits: [Part] = []
        var bytes: Int64 = 0
        for segment in segments {
            bytes += size(of: segment.part)
            if let initPart = segment.initPart, !inits.contains(initPart) {
                inits.append(initPart)
                bytes += size(of: initPart)
            }
        }
        return VideoHLSLocalStream(segments: segments, sourceBytes: bytes)
    }

    // MARK: - Tiện ích

    /// URI trong playlist local là tên file cùng thư mục; URI mạng ⇒ bản tải hỏng (đoạn chưa nằm trên máy).
    private static func localFile(_ uri: String, resolve: (String) -> URL?) throws -> URL {
        let name = (uri as NSString).lastPathComponent
        guard !uri.contains("://"), let url = resolve(uri) else { throw StreamError.missingFile(name) }
        return url
    }

    private static func keyBytes(_ uri: String, cache: inout [String: Data], resolve: (String) -> URL?) throws -> Data {
        if let cached = cache[uri] { return cached }
        let bytes: Data
        if uri.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("data:") {
            guard let decoded = dataURIBytes(uri) else { throw StreamError.invalidKey("data URI") }
            bytes = decoded
        } else {
            bytes = try Data(contentsOf: try localFile(uri, resolve: resolve))
        }
        guard bytes.count == 16 else { throw StreamError.invalidKey("\(bytes.count) byte") }
        cache[uri] = bytes
        return bytes
    }

    /// `data:[mime][;base64],payload` → byte (base64/base64url thiếu padding, hoặc percent-encoding).
    private static func dataURIBytes(_ uri: String) -> Data? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comma = trimmed.firstIndex(of: ",") else { return nil }
        let header = trimmed[..<comma].lowercased()
        let payload = String(trimmed[trimmed.index(after: comma)...])
        if header.contains(";base64") {
            var normalized = (payload.removingPercentEncoding ?? payload)
                .components(separatedBy: .whitespacesAndNewlines).joined()
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            if normalized.count % 4 > 0 {
                normalized += String(repeating: "=", count: 4 - normalized.count % 4)
            }
            return Data(base64Encoded: normalized)
        }
        let input = Array(payload.utf8)
        var bytes = Data(capacity: input.count)
        var index = 0
        while index < input.count {
            if input[index] == UInt8(ascii: "%"), index + 2 < input.count,
               let value = UInt8(String(decoding: input[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) {
                bytes.append(value)
                index += 3
            } else {
                bytes.append(input[index])
                index += 1
            }
        }
        return bytes
    }

    /// `IV=0x…` → 16 byte (thiếu chữ số thì đệm 0 bên trái).
    private static func parseIV(_ raw: String) throws -> Data {
        var hex = raw.trimmingCharacters(in: .whitespaces)
        if hex.lowercased().hasPrefix("0x") { hex = String(hex.dropFirst(2)) }
        guard !hex.isEmpty, hex.count <= 32, hex.allSatisfy(\.isHexDigit) else { throw StreamError.invalidKey("IV") }
        hex = String(repeating: "0", count: 32 - hex.count) + hex
        var bytes = Data(capacity: 16)
        var cursor = hex.startIndex
        while cursor < hex.endIndex {
            let next = hex.index(cursor, offsetBy: 2)
            guard let value = UInt8(hex[cursor..<next], radix: 16) else { throw StreamError.invalidKey("IV") }
            bytes.append(value)
            cursor = next
        }
        return bytes
    }

    /// IV ngầm của AES-128: số thứ tự media sequence của đoạn, big-endian 16 byte.
    private static func sequenceIV(_ sequence: Int64) -> Data {
        var bytes = Data(repeating: 0, count: 8)
        let value = UInt64(bitPattern: sequence)
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
        return bytes
    }

    /// `n[@o]`.
    private static func parseByteRange(_ raw: String) -> (length: Int64, offset: Int64?)? {
        let parts = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")).split(separator: "@")
        guard let first = parts.first, let length = Int64(first), length > 0 else { return nil }
        return (length, parts.count > 1 ? Int64(parts[1]) : nil)
    }

    private static func size(of part: Part) -> Int64 {
        if let range = part.byteRange { return range.length }
        return Int64((try? part.file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    /// Chuẩn hoá xuống dòng, bỏ BOM, thụt lề và dòng trống.
    private static func lines(of text: String) -> [String] {
        VideoDataURI.stripBOM(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
