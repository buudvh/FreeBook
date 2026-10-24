import Foundation
import Network

/// Xử lý **một** kết nối của `VideoOfflineHTTPServer`: đọc request tới `\r\n\r\n` (tối đa 16 KB), kiểm token, trả file
/// dưới `videos/` rồi đóng kết nối (`Connection: close`). Hỗ trợ `GET`/`HEAD` và một khoảng `Range: bytes=a-b` /
/// `bytes=a-` (206 + `Content-Range`); luôn gửi `Accept-Ranges` + `Content-Length`; không nén. Thân file đọc theo khối
/// 256 KB, gửi khối kế khi khối trước đã đi. Chạy trên queue của server.
final class VideoOfflineHTTPResponder: @unchecked Sendable {
    private static let maxHeaderBytes = 16 * 1024
    private static let chunkSize = 256 * 1024
    private static let headerTerminator = Data("\r\n\r\n".utf8)

    private let connection: NWConnection
    private let token: String
    private var buffer = Data()

    init(connection: NWConnection, token: String) {
        self.connection = connection
        self.token = token
    }

    func start() {
        receive()
    }

    // MARK: - Đọc request

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxHeaderBytes) { [self] data, _, isComplete, error in
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Self.headerTerminator) {
                handleRequest(String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self))
            } else if error != nil || isComplete || buffer.count > Self.maxHeaderBytes {
                connection.cancel()
            } else {
                receive()
            }
        }
    }

    private func handleRequest(_ head: String) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2 else { return respondStatus(400, "Bad Request") }
        let method = parts[0].uppercased()
        guard method == "GET" || method == "HEAD" else { return respondStatus(405, "Method Not Allowed") }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let rawPath = String(parts[1].split(separator: "?", maxSplits: 1).first ?? "")
        let components = rawPath.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        guard components.count >= 2, components[0] == token, !components.contains("..") else {
            AppLogger.shared.log("❌ [VideoOfflineServer] Từ chối request sai token/đường dẫn")
            return respondStatus(403, "Forbidden")
        }
        let relativePath = components.dropFirst().joined(separator: "/")
        var isDirectory: ObjCBool = false
        guard let fileURL = VideoOfflineStore.resolveRelativePath(relativePath),
              FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            AppLogger.shared.log("❌ [VideoOfflineServer] Không có file: \((relativePath as NSString).lastPathComponent)")
            return respondStatus(404, "Not Found")
        }
        let size = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber)?.int64Value ?? 0
        serveFile(fileURL, size: size, range: headers["range"], headOnly: method == "HEAD")
    }

    // MARK: - Trả lời

    private func serveFile(_ url: URL, size: Int64, range rangeHeader: String?, headOnly: Bool) {
        var start: Int64 = 0
        var end: Int64 = max(0, size - 1)
        var status = "200 OK"
        var extraHeaders: [String] = []
        if let rangeHeader {
            guard let parsed = Self.parseRange(rangeHeader, size: size) else {
                return respondStatus(416, "Range Not Satisfiable", extraHeaders: ["Content-Range: bytes */\(size)"])
            }
            start = parsed.start
            end = parsed.end
            status = "206 Partial Content"
            extraHeaders.append("Content-Range: bytes \(start)-\(end)/\(size)")
        }
        let length = size == 0 ? 0 : end - start + 1
        var head = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(Self.contentType(for: url))",
            "Content-Length: \(length)",
            "Accept-Ranges: bytes",
            "Connection: close"
        ]
        head += extraHeaders
        let headerData = Data((head.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        guard !headOnly, length > 0, let handle = try? FileHandle(forReadingFrom: url) else {
            return send(headerData, then: nil)
        }
        do {
            try handle.seek(toOffset: UInt64(start))
        } catch {
            try? handle.close()
            AppLogger.shared.log("❌ [VideoOfflineServer] Không đọc được \(url.lastPathComponent): \(error.localizedDescription)")
            return respondStatus(500, "Internal Server Error")
        }
        send(headerData) { [self] in
            sendBody(handle, remaining: length)
        }
    }

    private func sendBody(_ handle: FileHandle, remaining: Int64) {
        guard remaining > 0 else {
            try? handle.close()
            finish()
            return
        }
        let count = Int(min(Int64(Self.chunkSize), remaining))
        let chunk: Data
        do {
            chunk = try handle.read(upToCount: count) ?? Data()
        } catch {
            try? handle.close()
            AppLogger.shared.log("❌ [VideoOfflineServer] Lỗi đọc file khi phát: \(error.localizedDescription)")
            connection.cancel()
            return
        }
        guard !chunk.isEmpty else {
            try? handle.close()
            finish()
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [self] error in
            if error != nil {
                // AVPlayer hay đóng kết nối giữa chừng khi tua — không phải lỗi cần log.
                try? handle.close()
                connection.cancel()
                return
            }
            sendBody(handle, remaining: remaining - Int64(chunk.count))
        })
    }

    private func respondStatus(_ code: Int, _ reason: String, extraHeaders: [String] = []) {
        let head = ["HTTP/1.1 \(code) \(reason)", "Content-Length: 0", "Connection: close"] + extraHeaders
        send(Data((head.joined(separator: "\r\n") + "\r\n\r\n").utf8), then: nil)
    }

    private func send(_ data: Data, then next: (() -> Void)?) {
        connection.send(content: data, completion: .contentProcessed { [self] error in
            guard error == nil else {
                connection.cancel()
                return
            }
            if let next { next() } else { finish() }
        })
    }

    private func finish() {
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [self] _ in
            connection.cancel()
        })
    }

    // MARK: - Tiện ích

    /// `bytes=a-b`, `bytes=a-`, `bytes=-n` (một khoảng). Ngoài file ⇒ `nil` (416).
    private static func parseRange(_ header: String, size: Int64) -> (start: Int64, end: Int64)? {
        let value = header.trimmingCharacters(in: .whitespaces).lowercased()
        guard value.hasPrefix("bytes="), size > 0 else { return nil }
        let spec = value.dropFirst("bytes=".count).split(separator: ",").first.map(String.init) ?? ""
        let bounds = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard bounds.count == 2 else { return nil }
        if bounds[0].isEmpty {
            guard let suffix = Int64(bounds[1]), suffix > 0 else { return nil }
            return (max(0, size - suffix), size - 1)
        }
        guard let start = Int64(bounds[0]), start < size else { return nil }
        let end = bounds[1].isEmpty ? size - 1 : min(size - 1, Int64(bounds[1]) ?? (size - 1))
        guard end >= start else { return nil }
        return (start, end)
    }

    private static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m3u8": return "application/vnd.apple.mpegurl"
        case "ts": return "video/mp2t"
        case "m4s", "mp4": return "video/mp4"
        case "aac": return "audio/aac"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "ac3": return "audio/ac3"
        case "ec3": return "audio/eac3"
        case "vtt": return "text/vtt"
        default: return "application/octet-stream"
        }
    }
}
