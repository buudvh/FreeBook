import Foundation

/// Kiểm tra đường dẫn trước mọi thao tác file của phân hệ nguồn Legado.
///
/// Repo này **cài lại `validatePathSafety` độc lập ở từng owner** (`BookBinManager`,
/// `ImageCacheManager`, `BookStorageManager`, `ChapterStorePath`) — sửa một chỗ không lan sang chỗ
/// khác. File này là bản của phân hệ Legado, giữ đúng quy ước đó thay vì chia sẻ code.
public enum LegadoPathSafety {

    /// Đường dẫn phải nằm **thật sự** bên trong thư mục gốc cho phép và không chứa `..`.
    public static func validate(_ url: URL, mustBeUnder root: URL) -> Bool {
        let target = url.standardizedFileURL.resolvingSymlinksInPath().path
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        guard !target.contains("..") else { return false }
        guard target.hasPrefix(base) else { return false }
        // Chặn trường hợp tên thư mục chỉ *bắt đầu* giống nhau (`/a/bc` với gốc `/a/b`).
        if target.count > base.count {
            let boundary = target[target.index(target.startIndex, offsetBy: base.count)]
            guard boundary == "/" else { return false }
        }
        return true
    }

    /// Tên file/thư mục an toàn từ một chuỗi tuỳ ý (dùng cho `packageId`).
    public static func sanitizeComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))
        let filtered = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let text = String(filtered)
        return text.isEmpty ? "unnamed" : String(text.prefix(96))
    }
}
