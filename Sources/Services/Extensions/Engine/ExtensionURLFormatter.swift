import Foundation

/// Chuẩn hoá URL ảnh/link do extension trả về: lấy `http(s)://` cuối cùng khi bị lặp, ghép `host` cho URL tương đối.
/// Chuyển nguyên văn từ `JSExecutor.cleanAndResolveUrl` (1.3.481) — hàm đó còn là forwarder công khai cho caller cũ.
enum ExtensionURLFormatter {
    static func cleanAndResolve(_ urlString: String, host: String? = nil) -> String {
        var cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Nếu chứa nhiều hơn 1 http:// hoặc https://, lấy cái cuối cùng
        let patterns = ["https://", "http://"]
        var lastIndex: String.Index? = nil

        for pattern in patterns {
            var searchRange = cleaned.startIndex..<cleaned.endIndex
            while let range = cleaned.range(of: pattern, options: .backwards, range: searchRange) {
                if lastIndex == nil || range.lowerBound > lastIndex! {
                    lastIndex = range.lowerBound
                }
                searchRange = cleaned.startIndex..<range.lowerBound
            }
        }

        if let idx = lastIndex, idx != cleaned.startIndex {
            cleaned = String(cleaned[idx...])
        }

        // 2. Nếu là URL tương đối (không bắt đầu bằng http:// hoặc https://)
        if !cleaned.lowercased().hasPrefix("http://") && !cleaned.lowercased().hasPrefix("https://") {
            let foundHost = host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !foundHost.isEmpty {
                let separator = cleaned.hasPrefix("/") || foundHost.hasSuffix("/") ? "" : "/"
                cleaned = foundHost + separator + cleaned
            }
        }

        return cleaned
    }
}
