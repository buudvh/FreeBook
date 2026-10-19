import Foundation

/// Một bộ lọc quảng cáo trong danh mục **cố định** của trình duyệt — bộ lọc AdGuard bản tối ưu cho iOS
/// (`https://filters.adtidy.org/ios/filters/<id>_optimized.txt`).
///
/// `id` là filterId của AdGuard và là thứ **duy nhất** dùng để dựng tên file/định danh (`filters/<id>.txt`,
/// `adblock-<id>`, `adguard-<id>.txt`) — không bao giờ nhận đường dẫn hay tên từ người dùng.
struct AdBlockFilter: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let defaultEnabled: Bool
    /// Chữ phụ cảnh báo khi bộ chưa tải (chỉ Tracking Protection).
    let note: String?

    /// URL tải bản tối ưu cho iOS.
    var subscriptionURL: URL {
        URL(string: "https://filters.adtidy.org/ios/filters/\(id)_optimized.txt")!
    }

    /// Tên resource `.txt` của bản đóng gói kèm app (`Sources/Resources/AdBlock/adguard-<id>.txt`); `nil` với bộ
    /// không đóng gói (chỉ có sau khi tải). Danh sách phải khớp `Scripts/update_adblock_snapshot.py`.
    var bundledResourceName: String? {
        Self.bundledFilterIds.contains(id) ? "adguard-\(id)" : nil
    }

    /// Đúng thứ tự hiển thị trong màn Cài đặt → Trình duyệt.
    static let catalog: [AdBlockFilter] = [
        AdBlockFilter(id: 2, name: "AdGuard Base", defaultEnabled: true, note: nil),
        AdBlockFilter(id: 11, name: "AdGuard Mobile Ads", defaultEnabled: true, note: nil),
        AdBlockFilter(id: 214, name: "ABPVN (tiếng Việt)", defaultEnabled: true, note: nil),
        AdBlockFilter(id: 224, name: "AdGuard Chinese", defaultEnabled: true, note: nil),
        AdBlockFilter(id: 19, name: "AdGuard Popups", defaultEnabled: false, note: nil),
        AdBlockFilter(id: 18, name: "AdGuard Cookie Notices", defaultEnabled: false, note: nil),
        AdBlockFilter(id: 3, name: "AdGuard Tracking Protection", defaultEnabled: false, note: "Nặng, dễ lỗi trang"),
    ]

    /// Các bộ bật sẵn, theo thứ tự danh mục — giá trị mặc định của `WebContentSettings.enabledFilterIdsKey`.
    static var defaultEnabledIds: [Int] {
        catalog.filter(\.defaultEnabled).map(\.id)
    }

    static func filter(id: Int) -> AdBlockFilter? {
        catalog.first(where: { $0.id == id })
    }

    /// Bốn bộ có bản đóng gói (`adguard-<id>.txt`).
    private static let bundledFilterIds: Set<Int> = [2, 11, 214, 224]
}
