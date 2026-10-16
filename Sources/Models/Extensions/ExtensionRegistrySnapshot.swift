import Foundation

/// Cache nguyên văn registry của **một** kho (`extension_store/registry/<sha256(url)>.json`).
///
/// Dữ liệu tải lại được, không quý: hỏng thì bị cách ly và kho chỉ trống tới lần làm mới kế tiếp. Nhờ cache này
/// tab Tiện ích vẫn liệt kê tiện ích chưa cài khi offline, và cooldown làm mới kho vẫn có tác dụng.
public struct ExtensionRegistrySnapshot: Codable, Sendable {
    public var url: String
    public var fetchedAt: Date
    public var items: [ExtensionRegistryItem]

    public init(url: String, fetchedAt: Date = Date(), items: [ExtensionRegistryItem]) {
        self.url = url
        self.fetchedAt = fetchedAt
        self.items = items
    }
}
