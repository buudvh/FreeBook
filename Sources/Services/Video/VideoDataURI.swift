import Foundation

/// Giải mã URI `data:` dạng text (playlist HLS, phụ đề) mà ext video trả về: `data:<mime>[;charset=…][;base64],<payload>`.
/// Payload base64 (chấp nhận cả base64url, thiếu padding, xuống dòng) hoặc percent-encoded.
enum VideoDataURI {
    struct Decoded: Sendable {
        /// MIME viết thường, rỗng nếu URI không khai.
        let mimeType: String
        let text: String

        /// Playlist HLS: MIME `*mpegurl*` hoặc nội dung mở đầu bằng `#EXTM3U`.
        var isHLSPlaylist: Bool {
            mimeType.contains("mpegurl") || VideoDataURI.stripBOM(text).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U")
        }
    }

    static func isDataURI(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(5).lowercased() == "data:"
    }

    /// `nil` khi không phải URI `data:` hoặc payload không giải được thành text UTF-8.
    static func decode(_ value: String) -> Decoded? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isDataURI(trimmed), let comma = trimmed.firstIndex(of: ",") else { return nil }
        let header = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 5)..<comma].lowercased()
        let payload = String(trimmed[trimmed.index(after: comma)...])
        let parameters = header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        let mimeType = parameters.first.map { $0.contains("=") ? "" : $0 } ?? ""

        let text: String?
        if parameters.contains("base64") {
            text = decodeBase64(payload.removingPercentEncoding ?? payload)
        } else {
            text = payload.removingPercentEncoding ?? payload
        }
        guard let text else { return nil }
        return Decoded(mimeType: mimeType, text: text)
    }

    static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    private static func decodeBase64(_ payload: String) -> String? {
        var normalized = payload
            .components(separatedBy: .whitespacesAndNewlines).joined()
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: normalized) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}
