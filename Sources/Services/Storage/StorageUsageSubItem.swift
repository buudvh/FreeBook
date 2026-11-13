import Foundation

/// Một dòng cháu của màn Dung lượng (chỉ để xem): dưới dòng con "Bộ đệm hệ thống" là các thư mục lớn nhất của
/// `Library/Caches` theo tên dễ hiểu (`SystemCacheTally`), dưới "Không rõ chủ" là các đường dẫn lớn nhất (tương đối với thư
/// mục nhà, vd `Documents/Inbox`).
///
/// Nằm trong `StorageUsageDetail.children` (tuỳ chọn ⇒ bản đo đã lưu từ trước vẫn giải được). Chỉ giữ tên / đường dẫn
/// **tương đối**, không giữ đường dẫn container.
public struct StorageUsageSubItem: Sendable, Codable {
    public let title: String
    public let bytes: Int64

    /// `limit` mục lớn nhất của `tally` + một dòng `remainderTitle` cho phần còn lại, cắt theo `total` (= số của dòng cha
    /// đang hiện, có thể đã bị cắt) ⇒ các dòng cháu cộng lại luôn đúng bằng dòng cha. `nil` khi không có gì để chia.
    static func top(
        _ tally: [String: Int64],
        total: Int64,
        limit: Int = 4,
        remainderTitle: String
    ) -> [StorageUsageSubItem]? {
        var remaining = max(0, total)
        let sorted = tally
            .filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        guard remaining > 0, !sorted.isEmpty else { return nil }
        var items: [StorageUsageSubItem] = []
        for (title, bytes) in sorted.prefix(limit) {
            let value = min(bytes, remaining)
            guard value > 0 else { break }
            items.append(StorageUsageSubItem(title: title, bytes: value))
            remaining -= value
        }
        if remaining > 0 {
            items.append(StorageUsageSubItem(title: remainderTitle, bytes: remaining))
        }
        return items.isEmpty ? nil : items
    }
}
