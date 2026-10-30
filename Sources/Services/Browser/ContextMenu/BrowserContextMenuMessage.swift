import CoreGraphics
import Foundation

/// Một message của script menu nhấn giữ (`BrowserContextMenuScript`, handler `fbContextMenu`). Sai dạng ⇒ `nil`.
enum BrowserContextMenuMessage {
    /// Vùng chọn đổi. `text` rỗng = không còn vùng chọn. `text` chỉ là bản xem trước (cắt 2 000 ký tự) để menu quyết
    /// hiện mục nào — hành động lấy lại vùng chọn đầy đủ lúc bấm. `sourceHasHan`: chữ có Hán hoặc trang đang dịch.
    case selection(text: String, linkURL: URL?, sourceHasHan: Bool)
    /// `touchstart` trên ảnh; `linkURL` = link bao quanh ảnh (nếu có).
    case touch(imageURL: URL, linkURL: URL?)
    /// Nhấn giữ ảnh không nằm trong link; `pagePoint` = toạ độ tài liệu (CSS px) của điểm chạm.
    case imageHold(imageURL: URL, pagePoint: CGPoint)

    init?(body: Any) {
        guard let dictionary = body as? [String: Any], let type = dictionary["type"] as? String else { return nil }
        switch type {
        case "selection":
            let text = (dictionary["text"] as? String) ?? ""
            let link = Self.url(dictionary["link"])
            let han = (dictionary["han"] as? Bool) ?? false
            self = .selection(text: text, linkURL: link, sourceHasHan: han)
        case "touch":
            guard let image = Self.url(dictionary["image"]) else { return nil }
            self = .touch(imageURL: image, linkURL: Self.url(dictionary["link"]))
        case "imageHold":
            guard let image = Self.url(dictionary["image"]) else { return nil }
            let x = (dictionary["x"] as? NSNumber)?.doubleValue ?? 0
            let y = (dictionary["y"] as? NSNumber)?.doubleValue ?? 0
            self = .imageHold(imageURL: image, pagePoint: CGPoint(x: x, y: y))
        default:
            return nil
        }
    }

    private static func url(_ value: Any?) -> URL? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return URL(string: text)
    }
}
