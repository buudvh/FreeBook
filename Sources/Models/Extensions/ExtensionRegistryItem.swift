import Foundation

/// Một dòng trong registry (`plugin.json` cấp kho) của một kho tiện ích.
///
/// Chuyển từ `ExtensionManager.swift` sang Models vì giờ nó còn là dữ liệu **lưu đĩa**: cache registry của
/// từng kho (`ExtensionRegistrySnapshot`) giữ nguyên văn danh sách này để tab Tiện ích dựng được danh mục
/// tiện ích chưa cài khi offline. Tên field giữ nguyên để decode được JSON registry thật.
public struct ExtensionRegistryItem: Codable, Sendable, Hashable {
    public let name: String
    public let author: String?
    public let path: String // Link tải file plugin.zip
    public let version: Int?
    public let source: String? // URL trang web nguồn (ví dụ: https://truyenfull.vn)
    public let icon: String?
    public let description: String?
    public let type: String? // "novel", "chinese_novel", "comic", "tts"
    public let locale: String? // "vi_VN", "zh_CN", ...

    public init(
        name: String,
        author: String? = nil,
        path: String,
        version: Int? = nil,
        source: String? = nil,
        icon: String? = nil,
        description: String? = nil,
        type: String? = nil,
        locale: String? = nil
    ) {
        self.name = name
        self.author = author
        self.path = path
        self.version = version
        self.source = source
        self.icon = icon
        self.description = description
        self.type = type
        self.locale = locale
    }
}
