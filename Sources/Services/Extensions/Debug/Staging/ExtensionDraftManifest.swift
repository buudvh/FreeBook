import Foundation

/// Manifest của một snapshot nháp gửi từ máy phát triển (Phase 3).
///
/// Client khai **trước** toàn bộ file sẽ gửi, kèm size và SHA-256. Nhờ vậy server biết đủ để từ chối
/// ngay trước khi nhận byte nào: quá quota, path không an toàn, hoặc thiếu `plugin.json`. Không có
/// đường nào để client gửi một file không khai trong manifest.
public struct ExtensionDraftManifest: Codable, Sendable, Equatable {
    /// Trần của một snapshot. Extension VBook là vài chục KB JS; 4 MiB đã rất rộng.
    public static let maxTotalBytes = 4 * 1024 * 1024
    public static let maxFileCount = 200
    public static let maxFileBytes = 1024 * 1024

    public struct Entry: Codable, Sendable, Equatable {
        /// Path **tương đối**, dùng `/`. Server tự kiểm tra containment; client không được gửi path
        /// tuyệt đối hay `..`.
        public let relativePath: String
        public let size: Int
        public let sha256: String

        public init(relativePath: String, size: Int, sha256: String) {
            self.relativePath = relativePath
            self.size = size
            self.sha256 = sha256
        }
    }

    public let packageId: String
    /// Định danh bản nháp do client sinh (hash nội dung workspace). Server dùng nó làm tên thư mục
    /// staging và là thứ `run.start` tham chiếu tới.
    public let revision: String
    public let entries: [Entry]

    public init(packageId: String, revision: String, entries: [Entry]) {
        self.packageId = packageId
        self.revision = revision
        self.entries = entries
    }

    public var totalBytes: Int {
        entries.reduce(0) { $0 + $1.size }
    }

    /// Những vấn đề thuộc **trần dung lượng**, tách riêng khỏi phần còn lại của `shapeIssues()`.
    ///
    /// Vì sao phải tách: "workspace quá to" và "manifest sai" là hai việc người dùng phải làm khác
    /// nhau — một cái bớt file, một cái sửa manifest. Giao thức khai `QUOTA_EXCEEDED` cho đúng ca đầu
    /// từ đầu mà **chưa chỗ nào phát**; đo bằng client thật: manifest 300 file trả `DRAFT_INVALID`.
    public func quotaIssues() -> [String] {
        var issues: [String] = []
        if entries.count > Self.maxFileCount {
            issues.append("quá \(Self.maxFileCount) file")
        }
        if totalBytes > Self.maxTotalBytes {
            issues.append("tổng \(totalBytes) byte vượt trần \(Self.maxTotalBytes)")
        }
        for entry in entries where entry.size > Self.maxFileBytes {
            issues.append("\(entry.relativePath): \(entry.size) byte vượt trần \(Self.maxFileBytes) mỗi file")
        }
        return issues
    }

    /// Kiểm tra hình dạng manifest **trước** khi nhận byte. Trả danh sách vấn đề; rỗng là hợp lệ.
    ///
    /// Vấn đề dung lượng xếp **trước** để `message` của reply (lấy phần tử đầu) gọi đúng cái chặn
    /// người dùng, thay vì một chi tiết manifest nhỏ đứng chen lên trước.
    public func shapeIssues() -> [String] {
        var issues: [String] = quotaIssues()
        if packageId.isEmpty { issues.append("packageId rỗng") }
        if revision.isEmpty || revision.count > 64 { issues.append("revision rỗng hoặc quá dài") }
        if entries.isEmpty { issues.append("manifest không có file nào") }
        if !entries.contains(where: { $0.relativePath == "plugin.json" }) {
            issues.append("thiếu plugin.json ở gốc snapshot")
        }
        for entry in entries {
            // Size âm là manifest **sai**, không phải vượt trần — trần đã xét ở `quotaIssues()`.
            if entry.size < 0 {
                issues.append("\(entry.relativePath): size \(entry.size) không hợp lệ")
            }
            if entry.sha256.count != 64 {
                issues.append("\(entry.relativePath): sha256 không đúng 64 ký tự")
            }
            if let reason = Self.pathIssue(entry.relativePath) {
                issues.append("\(entry.relativePath): \(reason)")
            }
        }
        return issues
    }

    /// Chặn traversal, path tuyệt đối, ký tự rỗng và tên component nguy hiểm. Symlink không thể tồn
    /// tại vì server **tự tạo** từng file từ byte nhận được, không giải nén archive nào.
    public static func pathIssue(_ path: String) -> String? {
        if path.isEmpty { return "path rỗng" }
        if path.count > 200 { return "path quá dài" }
        if path.hasPrefix("/") || path.hasPrefix("~") { return "path tuyệt đối" }
        if path.contains("\\") { return "dùng dấu \\ thay vì /" }
        if path.contains("\0") { return "chứa ký tự NUL" }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        for component in components {
            if component.isEmpty { return "có component rỗng" }
            if component == "." || component == ".." { return "chứa . hoặc .." }
            if component.hasPrefix(".") { return "component ẩn: \(component)" }
        }
        return nil
    }
}
