import Foundation

/// Một tiện ích JS gom thành **một file** `extensions/js/<packageId>.json`:
///
/// ```json
/// { "bundleFormat": 1,
///   "files": { "plugin.json": "<nguyên văn>", "src/search.js": "…" },
///   "icon": "<base64 của icon.png, có thể vắng>" }
/// ```
///
/// - `files`: đường dẫn **tương đối** trong gói → nội dung chữ. Chỉ gom `plugin.json` và mọi file `*.js` (giữ đường
///   dẫn): JS chỉ đọc được file qua `load()`, mà `load()` chỉ chạy file JS.
/// - `plugin.json` giữ **nguyên văn**: `ExtensionConfigSchema` hiện mục cài đặt theo thứ tự khoá gốc của file, parse
///   lại là mất thứ tự.
/// - Đọc qua `ExtensionPackageReader` (đọc được cả thư mục cũ lẫn file này), không tự giải mã ở nơi khác.
public struct ExtensionPackageBundle: Codable, Sendable, Equatable {
    /// Phiên bản định dạng do app ghi hiện nay.
    public static let currentFormat = 1
    /// Đường dẫn tương đối của manifest trong gói.
    public static let manifestPath = "plugin.json"
    /// Tên file icon trong thư mục tiện ích (trong file gói là trường `icon`, không nằm trong `files`).
    public static let iconPath = "icon.png"

    public var bundleFormat: Int
    public var files: [String: String]
    /// Base64 của `icon.png`; `nil` khi tiện ích không có icon.
    public var icon: String?

    public init(bundleFormat: Int = ExtensionPackageBundle.currentFormat, files: [String: String], icon: String? = nil) {
        self.bundleFormat = bundleFormat
        self.files = files
        self.icon = icon
    }

    /// Nội dung chữ của `plugin.json`; `nil` khi gói không mang manifest.
    public var manifestText: String? {
        files[Self.manifestPath]
    }

    /// Bytes của `icon.png`; `nil` khi vắng hoặc base64 hỏng.
    public var iconData: Data? {
        guard let icon, !icon.isEmpty else { return nil }
        return Data(base64Encoded: icon, options: [.ignoreUnknownCharacters])
    }

    /// Đọc bytes của file gói. Ném khi không phải JSON đúng định dạng.
    public static func decode(from data: Data) throws -> ExtensionPackageBundle {
        try JSONDecoder().decode(ExtensionPackageBundle.self, from: data)
    }

    /// Bytes để ghi file gói: khoá sắp xếp, `prettyPrinted` (mở bằng app Tệp vẫn đọc được), không escape `/`.
    public func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
