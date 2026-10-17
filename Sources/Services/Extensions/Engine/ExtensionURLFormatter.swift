import Foundation

/// Chuẩn hoá URL do extension trả về.
/// - `cleanAndResolve` (link/URL lúc gọi script): lấy `http(s)://` cuối cùng khi bị lặp, `//x` ⇒ `https://x`, ghép
///   `host` cho URL tương đối. Chuyển từ `JSExecutor.cleanAndResolveUrl` (1.3.481) — hàm đó còn là forwarder.
/// - `resolveAssetURL` (ảnh): xem chú thích hàm.
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

        // URL không giao thức `//cdn…` không phải đường dẫn tương đối: thêm `https:` thay vì ghép host.
        if cleaned.hasPrefix("//") {
            return "https:" + cleaned
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

    /// Chuẩn hoá URL **ảnh** (bìa, icon, ảnh trong mục khám phá) theo hợp đồng extension (extension-api.md):
    /// - URL `http(s)://` tuyệt đối giữ **nguyên văn** — không có bước "lấy `https://` cuối cùng" như
    ///   `cleanAndResolve` (bước đó làm hỏng bìa dạng proxy `…?url=https://…`);
    /// - `//cdn…` ⇒ `https://cdn…`; URI `data:` giữ nguyên;
    /// - còn lại là đường dẫn tương đối ⇒ ghép `host` (host rỗng ⇒ giữ nguyên chuỗi đã trim).
    ///
    /// **Không** dùng cho `link`/`url` của sách hay chương: đó là khoá nhận diện, phải giữ nguyên văn lúc parse.
    static func resolveAssetURL(_ raw: String, host: String?) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("data:") {
            return trimmed
        }
        if trimmed.hasPrefix("//") {
            return "https:" + trimmed
        }

        var base = host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !base.isEmpty else { return trimmed }
        if base.hasPrefix("//") { base = "https:" + base }
        while base.hasSuffix("/") { base.removeLast() }
        return trimmed.hasPrefix("/") ? base + trimmed : base + "/" + trimmed
    }
}
