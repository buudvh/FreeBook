import Foundation

/// Tên kho tiện ích lúc thêm kho (1.3.752): sheet "Nhập kho tiện ích" không còn ô tên — tên lấy từ `plugin.json` của kho.
///
/// Thứ tự: `metadata.name` → `metadata.author` → `owner/repo` khi link là GitHub (`raw.githubusercontent.com/<owner>/<repo>/…`
/// hoặc `github.com/<owner>/<repo>/…`) → tên miền → nguyên link. Chỉ dùng khi **thêm** kho: kho đã lưu giữ tên cũ, lượt
/// kiểm tra cập nhật không đổi tên (người dùng chọn). Không có chỗ sửa tên tay.
enum ExtensionRepositoryNaming {
    static func name(metadata: RegistryMetadata?, url: String) -> String {
        if let name = nonEmpty(metadata?.name) { return name }
        if let author = nonEmpty(metadata?.author) { return author }
        return fallbackName(url: url)
    }

    /// Kho không khai tên/tác giả: `owner/repo` cho link GitHub, tên miền cho link khác, nguyên link khi không đọc được.
    static func fallbackName(url: String) -> String {
        guard let components = URLComponents(string: url), let host = components.host?.lowercased(), !host.isEmpty else {
            return url
        }
        let segments = components.path.split(separator: "/").map(String.init)
        if Self.githubHosts.contains(host), segments.count >= 2 {
            return "\(segments[0])/\(segments[1])"
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static let githubHosts: Set<String> = ["raw.githubusercontent.com", "github.com", "www.github.com"]

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
