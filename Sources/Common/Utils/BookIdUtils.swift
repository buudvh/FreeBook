import Foundation

public struct BookIdUtils {
    /// Tạo mã Book ID chuẩn hóa trung tính từ extensionPackageId và detailUrl sử dụng SHA-256
    public static func make(extensionPackageId: String, detailUrl: String) -> String {
        let pkg = extensionPackageId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let url = detailUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if pkg.isEmpty && url.isEmpty { return "" }
        let rawKey = "\(pkg)|\(url)"
        let hashHex = rawKey.sha256()
        let prefix = pkg.isEmpty ? "book" : pkg
        return "\(prefix)_\(hashHex.prefix(16))"
    }
}
